// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Repository layer wrapping UniFFI bindings for Vauchi iOS
//
// This file is strictly frontend infrastructure: keychain bootstrapping,
// protected-data lifecycle, notification polling, error mapping, identity
// creation and authentication.
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
        }
    }

    /// Convert from MobileError to VauchiRepositoryError.
    ///
    /// `MobileError` was collapsed to 8 variants in vauchi-platform 0.20.3.
    /// We preserve the richer `VauchiRepositoryError` surface because tests
    /// still discriminate on specific cases (`.internalError`).
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

/// Repository class wrapping the single `PlatformAppEngine` UniFFI handle
class VauchiRepository {
    /// The app's one repository, shared by the foreground and background
    /// sync so one engine holds the database (vauchi/private#580).
    static let shared = SharedInstance<VauchiRepository>()

    // MARK: - Properties

    let appEngine: PlatformAppEngine
    private let dataDir: String
    private let relayUrl: String

    // MARK: - Initialization

    /// Initialize repository with data directory and relay URL.
    ///
    /// Core keeps every key that opens the database in `keychain`, so a
    /// shred that deletes them destroys access (vauchi/private#580). A locked
    /// keychain does not fail here: Core starts locked and shows its own
    /// unlock screen.
    init(
        dataDir: String? = nil,
        relayUrl: String = "https://relay.vauchi.app",
        keychain: MobilePlatformKeychain = VauchiKeychainBridge()
    ) throws {
        let dir = dataDir ?? VauchiRepository.defaultDataDir()
        self.dataDir = dir
        self.relayUrl = relayUrl

        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Single Rust handle (collapse-vauchi-platform G1): the engine owns
        // the one DB + key. Sync routes through `dispatchDomainCommand(.sync)`;
        // the legacy `VauchiPlatform` second handle is retired.
        do {
            appEngine = try PlatformAppEngine.openWithKeychain(
                dataDir: dir,
                relayUrl: relayUrl,
                shellStorageKey: nil,
                keychain: keychain
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }

        // S4 — wire `LocalizationService` to the live engine so locale
        // changes propagate to core via `setRenderContextJson`; Core keeps
        // the theme pick itself (vauchi/private#814). No vault → OS-native migration
        // is needed: the 2026-05-16 audit confirmed zero hand-written
        // `appPreferences()` callers on iOS, so the legacy vault
        // `app_preferences` row was never populated on this platform.
        // (Android needed a migration because its pre-S4 ThemeManager +
        // LocalizationManager read from the vault — see `android!407`.)
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
}

// MARK: - Platform Keychain Bridge

/// Adapts `KeychainService` to Core's `MobilePlatformKeychain`: Core keeps
/// every key that opens the database here (ADR-033).
///
/// Until Core stores its own bootstrap key, the bootstrap name is served from
/// the storage key this app kept itself before vauchi/private#580, and
/// deleting it deletes that key too.
class VauchiKeychainBridge: MobilePlatformKeychain {
    private static let bootstrapKeyName = "storage_bootstrap"
    private static let legacyStorageKeyName = "storage_key"

    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainService.shared) {
        self.keychain = keychain
    }

    func saveKey(name: String, key: Data) throws {
        do {
            try keychain.save(key: name, data: key)
        } catch {
            throw Self.keychainFailure("saveKey(\(name))", error)
        }
    }

    func loadKey(name: String) throws -> Data? {
        do {
            return try keychain.load(key: name)
        } catch KeychainServiceError.notFound {
            guard name == Self.bootstrapKeyName else { return nil }
            return try loadLegacyStorageKey()
        } catch {
            throw Self.keychainFailure("loadKey(\(name))", error)
        }
    }

    func deleteKey(name: String) throws {
        do {
            try keychain.delete(key: name)
            if name == Self.bootstrapKeyName {
                try keychain.delete(key: Self.legacyStorageKeyName)
            }
        } catch {
            throw Self.keychainFailure("deleteKey(\(name))", error)
        }
    }

    private func loadLegacyStorageKey() throws -> Data? {
        do {
            return try keychain.load(key: Self.legacyStorageKeyName)
        } catch KeychainServiceError.notFound {
            return nil
        } catch {
            throw Self.keychainFailure("loadKey(\(Self.bootstrapKeyName))", error)
        }
    }

    /// Names the failure for Core, which chooses the screen (ADR-045).
    private static func keychainFailure(_ operation: String, _ error: Error) -> KeychainError {
        if case KeychainServiceError.deviceLocked = error {
            return .AuthenticationRequired
        }
        return .OperationFailed(msg: "\(operation): \(error)")
    }
}
