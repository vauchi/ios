// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LocalAuthentication
import Security
import VauchiPlatform

/// The shell's answer to `Command::CreateUserPresenceSecret` /
/// `RevealUserPresenceSecret` (`core/vauchi-core/src/platform.rs`, #712).
enum UserPresenceOutcome: Equatable {
    case created(secret: [UInt8])
    case revealed(secret: [UInt8])
    case cancelled
    case unavailable

    /// Core's canonical `Event` JSON.
    var eventJson: String {
        hardwareEventJson(event: event)
    }

    private var event: MobileEvent {
        switch self {
        case let .created(secret):
            .userPresenceSecretCreated(secret: Data(secret))
        case let .revealed(secret):
            .userPresenceSecretRevealed(secret: Data(secret))
        case .cancelled:
            .userPresenceCheckCancelled
        case .unavailable:
            .hardwareUnavailable(transport: "user_presence")
        }
    }
}

struct UserPresenceKeychainRead {
    let status: OSStatus
    let secret: Data?
}

/// The keychain item whose every read needs the operating system's
/// user-presence check. Faked in tests: no unit test can pass that check.
protocol UserPresenceKeychain: AnyObject {
    /// Delete any previous item and store `secret` behind `.userPresence`.
    func replaceSecret(_ secret: Data) -> OSStatus
    /// Read the item, which runs the OS check with `prompt` as its reason.
    func readSecret(prompt: String) -> UserPresenceKeychainRead
}

/// Executes the two user-presence commands. The keychain read blocks while
/// the OS check is on screen, so it runs on `perform`'s queue, never main.
final class UserPresenceSecretService {
    static let secretLength = 32

    private let keychain: UserPresenceKeychain
    private let randomBytes: (Int) -> [UInt8]?
    private let perform: (@escaping () -> Void) -> Void

    init(
        keychain: UserPresenceKeychain = SystemUserPresenceKeychain(),
        randomBytes: @escaping (Int) -> [UInt8]? = secureRandomBytes,
        perform: @escaping (@escaping () -> Void) -> Void = {
            DispatchQueue.global(qos: .userInitiated).async(execute: $0)
        }
    ) {
        self.keychain = keychain
        self.randomBytes = randomBytes
        self.perform = perform
    }

    /// Whether this device can run the check at all: biometrics or, failing
    /// that, the device passcode.
    static func canSealUserPresence() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func create(prompt: String, completion: @escaping (UserPresenceOutcome) -> Void) {
        perform { [keychain, randomBytes] in
            guard var fresh = randomBytes(Self.secretLength), fresh.count == Self.secretLength else {
                completion(.unavailable)
                return
            }
            defer { Self.zero(&fresh) }
            guard keychain.replaceSecret(Data(fresh)) == errSecSuccess else {
                completion(.unavailable)
                return
            }
            // The read-back is the OS check Core asked to run now; a
            // mismatch means the item is not the one just sealed.
            let outcome = Self.outcome(of: keychain.readSecret(prompt: prompt)) { secret in
                secret == fresh ? .created(secret: secret) : .unavailable
            }
            completion(outcome)
        }
    }

    func reveal(prompt: String, completion: @escaping (UserPresenceOutcome) -> Void) {
        perform { [keychain] in
            completion(Self.outcome(of: keychain.readSecret(prompt: prompt)) { .revealed(secret: $0) })
        }
    }

    /// A cancel and a failed check both leave the user unconfirmed and free
    /// to retry, so both answer `UserPresenceCheckCancelled`
    /// (`LAError.userCancel` / `.appCancel` / `.systemCancel` reach the
    /// keychain caller as `errSecUserCanceled`). A missing or wrong-sized
    /// item, a locked keychain, or any other failure cannot produce the
    /// secret, so it answers `HardwareUnavailable` rather than handing Core
    /// bytes it would count as a wrong secret.
    private static func outcome(
        of read: UserPresenceKeychainRead,
        success: ([UInt8]) -> UserPresenceOutcome
    ) -> UserPresenceOutcome {
        switch read.status {
        case errSecSuccess:
            guard let data = read.secret, data.count == secretLength else { return .unavailable }
            return success([UInt8](data))
        case errSecUserCanceled, errSecAuthFailed:
            return .cancelled
        default:
            return .unavailable
        }
    }

    private static func zero(_ bytes: inout [UInt8]) {
        for index in bytes.indices {
            bytes[index] = 0
        }
    }
}

func secureRandomBytes(count: Int) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    return status == errSecSuccess ? bytes : nil
}

/// `.userPresence` admits biometrics or the device passcode, matching the
/// `deviceOwnerAuthentication` capability check (plan D4). `ThisDeviceOnly`
/// keeps the item out of backups and device migration: a restored Core asks
/// to reveal, finds nothing, and answers unavailable instead of trusting a
/// copied secret.
final class SystemUserPresenceKeychain: UserPresenceKeychain {
    private let service = "app.vauchi.ios"
    private let account = "user-presence-secret"

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func replaceSecret(_ secret: Data) -> OSStatus {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        ) else {
            return errSecParam
        }
        let deleted = SecItemDelete(itemQuery as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { return deleted }
        var attributes = itemQuery
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrAccessControl as String] = access
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func readSecret(prompt: String) -> UserPresenceKeychainRead {
        let context = LAContext()
        context.localizedReason = prompt
        // Every read must run the check again (plan D2: no reuse).
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return UserPresenceKeychainRead(status: status, secret: result as? Data)
    }
}
