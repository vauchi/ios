// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Repository layer wrapping UniFFI bindings for Vauchi iOS
//
// This file is strictly frontend infrastructure: keychain bootstrapping,
// protected-data lifecycle, notification polling, error mapping, identity
// creation, authentication, periodic sync, aha-moment surfacing, and the
// demo-contact init hook.
// All domain CRUD wrappers that were only exercised by tests have been
// retired; those actions now flow through core via `AppViewModel` and
// `dispatchDomainCommand` under the Humble-UI architecture (ADR-021/043).

import Foundation
import VauchiPlatform

/// Repository error types
enum VauchiRepositoryError: LocalizedError {
    case notInitialized
    case storageError(String)
    case cryptoError(String)
    case networkError(String)
    case invalidInput(String)
    case internalError(String)
    case rateLimited(UInt64)
    case deviceLocked

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Library not initialized"
        case let .storageError(msg):
            "Storage error: \(msg)"
        case let .cryptoError(msg):
            "Crypto error: \(msg)"
        case let .networkError(msg):
            "Network error: \(msg)"
        case let .invalidInput(msg):
            "Invalid input: \(msg)"
        case let .internalError(msg):
            "Internal error: \(msg)"
        case let .rateLimited(retryAfterSecs):
            "Rate limited — please wait \(retryAfterSecs)s before trying again"
        case .deviceLocked:
            "Device is locked — unlock your device to access Vauchi"
        }
    }

    /// Convert from MobileError to VauchiRepositoryError.
    ///
    /// `MobileError` was collapsed to 8 variants in vauchi-platform 0.20.3.
    /// We preserve the richer `VauchiRepositoryError` surface because several
    /// call sites and tests still discriminate on specific cases
    /// (`.rateLimited`, `.deviceLocked`).
    static func from(_ error: MobileError) -> VauchiRepositoryError {
        switch error {
        case .WrongPassword:
            return .cryptoError("Wrong password")
        case .DecryptFailed:
            return .cryptoError("Failed to decrypt — data may be corrupt or key mismatch")
        case let .InvalidInput(field, detail):
            return .invalidInput(field.isEmpty ? detail : "\(field): \(detail)")
        case .NetworkUnavailable:
            return .networkError("Network unavailable")
        case let .RelayError(status, detail):
            return .networkError("Relay error \(status): \(detail)")
        case let .RateLimited(retryAfterSecs):
            return .rateLimited(retryAfterSecs)
        case let .StorageError(detail):
            return .storageError(detail)
        case let .Other(detail):
            return .internalError(detail)
        @unknown default:
            return .internalError("Unknown error")
        }
    }
}

/// Sync result
struct VauchiSyncResult {
    let contactsAdded: UInt32
    let cardsUpdated: UInt32
    let updatesSent: UInt32
    let total: UInt32
    let hasChanges: Bool
    let updatedContactNames: [String]
}

/// Repository class wrapping the single `PlatformAppEngine` UniFFI handle
class VauchiRepository {
    // MARK: - Properties

    let appEngine: PlatformAppEngine
    private let dataDir: String
    private let relayUrl: String

    // MARK: - Initialization

    /// Initialize repository with data directory and relay URL
    /// Uses iOS Keychain for secure storage key management
    init(dataDir: String? = nil, relayUrl: String = "https://relay.vauchi.app") throws {
        let dir = dataDir ?? VauchiRepository.defaultDataDir()
        self.dataDir = dir
        self.relayUrl = relayUrl

        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Get storage key from Keychain (or migrate/generate)
        let storageKeyBytes = try VauchiRepository.getOrCreateStorageKey(dataDir: dir)

        // Single Rust handle (collapse-vauchi-platform G1): the engine owns
        // the one DB + key. Sync routes through `dispatchDomainCommand(.sync)`;
        // the legacy `VauchiPlatform` second handle is retired.
        do {
            appEngine = try PlatformAppEngine(
                dataDir: dir,
                relayUrl: relayUrl,
                storageKeyBytes: storageKeyBytes
            )
            // Wire the keychain so core-driven shred DomainCommands (SoftShred /
            // CancelShred / HardShred / PanicShred) reach the platform keychain.
            // `widget_panic_shred` is a free function and needs no instance.
            appEngine.setPlatformKeychain(keychain: VauchiKeychainBridge())
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }

        // S4 — wire `ThemeService` + `LocalizationService` to the live
        // engine so subsequent theme/locale changes propagate to core
        // via `setRenderContextJson`. No vault → OS-native migration
        // is needed: the 2026-05-16 audit confirmed zero hand-written
        // `appPreferences()` callers on iOS, so the legacy vault
        // `app_preferences` row was never populated on this platform.
        // (Android needed a migration because its pre-S4 ThemeManager +
        // LocalizationManager read from the vault — see `android!407`.)
        ThemeService.shared.attachAppEngine(appEngine)
        LocalizationService.shared.attachAppEngine(appEngine)

        // Report this device's exchange-relevant hardware to core so the
        // Exchange mode picker offers only modes the device can perform.
        // Without this push core falls back to `DeviceCapabilities::default()`
        // (all-false) — see `2026-05-23-exchange-capabilities-frontend-gap`.
        pushDeviceCapabilities(engine: appEngine)
    }

    /// Default data directory in Application Support
    static func defaultDataDir() -> String {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Vauchi")
        return appSupport.path
    }

    // MARK: - Secure Key Management

    /// Get or create storage key from Keychain.
    ///
    /// Key length and generation are owned by core via
    /// `mobileStorageKeyByteLength()` / `mobileGenerateStorageKey()` —
    /// both frontends share core's audited CSPRNG so key derivation
    /// stays consistent across platforms.
    static func getOrCreateStorageKey(dataDir _: String) throws -> Data {
        let keychain = KeychainService.shared
        let expectedKeyLength = Int(mobileStorageKeyByteLength())

        do {
            let keyData = try keychain.loadStorageKey()
            if keyData.count == expectedKeyLength {
                return keyData
            }
            // Key exists but wrong length — regenerate (migration scenario)
        } catch KeychainServiceError.notFound {
            // No key exists yet — first launch, generate below
        } catch KeychainServiceError.deviceLocked {
            // Device locked — DO NOT generate a new key, propagate the error
            throw VauchiRepositoryError.deviceLocked
        }
        // Other KeychainServiceError variants re-throw automatically

        // Generate new key and store in Keychain
        let newKeyData = mobileGenerateStorageKey()
        try keychain.saveStorageKey(newKeyData)

        return newKeyData
    }

    /// Handle app backgrounded event (C1 auto-lock)
    func handleAppBackgrounded() -> String? {
        do {
            return try appEngine.handleAppBackgrounded()
        } catch {
            #if DEBUG
                print("VauchiRepository: handleAppBackgrounded failed: \(error)")
            #endif
            return nil
        }
    }

    /// Poll for OS notifications produced by the app engine.
    func pollNotifications() -> [MobilePendingNotification] {
        do {
            return try appEngine.pollNotifications()
        } catch {
            #if DEBUG
                print("VauchiRepository: pollNotifications failed: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Identity Operations

    /// Check if identity exists
    func hasIdentity() -> Bool {
        (try? appEngine.hasIdentity()) ?? false
    }

    /// Create new identity with display name
    func createIdentity(displayName: String) throws {
        do {
            try appEngine.createIdentity(displayName: displayName)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Passcode (C6)

    /// Authenticate with password/PIN — returns "normal" or "duress", throws on invalid
    func authenticate(password: String) throws -> String {
        do {
            let mode = try appEngine.authenticate(password: password)
            switch mode {
            case .normal: return "normal"
            case .duress: return "duress"
            }
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Sync Operations

    /// Sync with relay server.
    ///
    /// Routes through the single engine handle. The engine lazily connects
    /// and honors the C1/C2 timing throttle: a throttled (`TooSoon`) call
    /// returns a benign no-change result (`hasChanges == false`), not an
    /// error.
    func sync() throws -> VauchiSyncResult {
        do {
            let dcResult = try appEngine.dispatchDomainCommand(command: .sync)
            guard case let .syncResult(result) = dcResult else {
                throw VauchiRepositoryError.from(
                    MobileError.Other(detail: "Sync: unexpected result variant")
                )
            }
            return VauchiSyncResult(
                contactsAdded: result.contactsAdded,
                cardsUpdated: result.cardsUpdated,
                updatesSent: result.updatesSent,
                total: result.total,
                hasChanges: result.hasChanges,
                updatedContactNames: result.updatedContactNames
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Aha Moments

    /// Try to trigger an aha moment and return the localized milestone if it
    /// should be shown now, or `nil` if already seen. Errors are swallowed so
    /// a milestone failure never breaks the calling flow.
    func tryTriggerAhaMoment(_ momentType: MobileAhaMomentType) -> MobileAhaMoment? {
        do {
            let result = try appEngine.dispatchDomainCommand(command: .tryTriggerAhaMoment(momentType: momentType))
            guard case let .ahaMomentOpt(moment) = result else { return nil }
            return moment
        } catch {
            return nil
        }
    }

    // MARK: - Demo Contact Operations

    // Based on: features/demo_contact.feature

    /// Initialize demo contact if user has no real contacts.
    /// Call this after onboarding completes.
    ///
    /// - Returns: The demo contact if created, nil if user has contacts or demo was dismissed
    func initDemoContactIfNeeded() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try appEngine.initDemoContactIfNeeded() else {
                return nil
            }
            return VauchiDemoContact(from: mobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }
}

// MARK: - Demo Contact Types

/// Demo contact for solo users demonstrating update flow
/// Based on: features/demo_contact.feature
struct VauchiDemoContact {
    /// Contact ID (always "demo-vauchi-tips")
    let id: String
    /// Display name (always "Vauchi Tips")
    let displayName: String
    /// Flag indicating this is a demo contact
    let isDemo: Bool
    /// Current tip title
    let tipTitle: String
    /// Current tip content
    let tipContent: String
    /// Tip category (e.g., "GettingStarted", "Privacy", "Updates")
    let tipCategory: String

    init(from mobile: MobileDemoContact) {
        id = mobile.id
        displayName = mobile.displayName
        isDemo = mobile.isDemo
        tipTitle = mobile.tipTitle
        tipContent = mobile.tipContent
        tipCategory = mobile.tipCategory
    }
}

// MARK: - Platform Keychain Bridge

/// Adapts `KeychainService` to the `MobilePlatformKeychain` callback interface
/// expected by core's crypto-shredding operations (SMK management).
class VauchiKeychainBridge: MobilePlatformKeychain {
    private let keychain = KeychainService.shared

    func saveKey(name: String, key: Data) throws {
        do {
            try keychain.save(key: name, data: key)
        } catch {
            throw KeychainError.OperationFailed(msg: "saveKey(\(name)): \(error)")
        }
    }

    func loadKey(name: String) throws -> Data? {
        do {
            return try keychain.load(key: name)
        } catch KeychainServiceError.notFound {
            return nil
        } catch {
            throw KeychainError.OperationFailed(msg: "loadKey(\(name)): \(error)")
        }
    }

    func deleteKey(name: String) throws {
        do {
            try keychain.delete(key: name)
        } catch {
            throw KeychainError.OperationFailed(msg: "deleteKey(\(name)): \(error)")
        }
    }
}
