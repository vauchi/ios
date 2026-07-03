// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Repository layer wrapping UniFFI bindings for Vauchi iOS
//
// DONE: Restore feature - core-driven via ExchangeCommand::FilePickFromUser +
// BackupPasswordEntry screen (ADR-031, file-picker plan 2026-05-03). The legacy
// `importBackup(data:password:)` repo/VM helpers remain available as direct
// UniFFI-layer wrappers (covered by VauchiRepositoryTests) but are no longer
// driven from the UI.
//
// DONE: Proximity verification - MobileProximityVerifier removed in core 0.19.21 (ADR-031).
// AudioProximityService retained with inherent methods; proximity API stubbed until
// command/event proximity protocol lands.
//
// DONE: Password strength indicator - checkPasswordStrength() integrated in ExportBackupSheet
// with PasswordStrengthIndicator component showing real-time visual feedback.
//
// DONE: Demo contact - implemented initDemoContactIfNeeded(), getDemoContact(),
// getDemoContactState(), isDemoUpdateAvailable(), triggerDemoUpdate(),
// dismissDemoContact(), autoRemoveDemoContact(), restoreDemoContact().
//
// DONE: Certificate pinning UI - isCertificatePinningEnabled(), setPinnedCertificate()
// methods implemented. UI added to Settings under Security section.

import Foundation
import VauchiPlatform

/// Repository error types
enum VauchiRepositoryError: LocalizedError {
    case notInitialized
    case alreadyInitialized
    case identityNotFound
    case contactNotFound(String)
    case invalidQrCode
    case exchangeFailed(String)
    case syncFailed(String)
    case storageError(String)
    case cryptoError(String)
    case networkError(String)
    case invalidInput(String)
    case internalError(String)
    case gdprError(String)
    case deletionNotAllowed(String)
    case shredError(String)
    case rateLimited(UInt64)
    case deviceLocked

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Library not initialized"
        case .alreadyInitialized:
            "Already initialized"
        case .identityNotFound:
            "Identity not found"
        case let .contactNotFound(id):
            "Contact not found: \(id)"
        case .invalidQrCode:
            "Invalid QR code"
        case let .exchangeFailed(msg):
            "Exchange failed: \(msg)"
        case let .syncFailed(msg):
            "Sync failed: \(msg)"
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
        case let .gdprError(msg):
            "GDPR error: \(msg)"
        case let .deletionNotAllowed(msg):
            "Deletion not allowed: \(msg)"
        case let .shredError(msg):
            "Shred error: \(msg)"
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
    /// (`.alreadyInitialized`, `.deviceLocked`). The extra cases simply stay
    /// reachable via other code paths (local guards, not the FFI).
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

/// Field type enum matching Rust MobileFieldType
enum VauchiFieldType: String, CaseIterable {
    case email
    case phone
    case website
    case address
    case social
    case birthday
    case custom

    var displayName: String {
        switch self {
        case .email: "Email"
        case .phone: "Phone"
        case .website: "Website"
        case .address: "Address"
        case .social: "Social"
        case .birthday: "Birthday"
        case .custom: "Custom"
        }
    }

    /// Convert to MobileFieldType
    var toMobile: MobileFieldType {
        switch self {
        case .email: .email
        case .phone: .phone
        case .website: .website
        case .address: .address
        case .social: .social
        case .birthday: .birthday
        case .custom: .custom
        }
    }

    /// Convert from MobileFieldType
    static func from(_ mobile: MobileFieldType) -> VauchiFieldType {
        switch mobile {
        case .email: .email
        case .phone: .phone
        case .website: .website
        case .address: .address
        case .social: .social
        case .birthday: .birthday
        case .custom: .custom
        }
    }
}

/// Contact field
struct VauchiContactField: Identifiable {
    let id: String
    let fieldType: VauchiFieldType
    let label: String
    let value: String
}

/// Contact card
struct VauchiContactCard {
    let displayName: String
    let fields: [VauchiContactField]
}

/// Contact
struct VauchiContact: Identifiable {
    let id: String
    let displayName: String
    let fingerprint: String
    let isVerified: Bool
    let isRecoveryTrusted: Bool
    let isHidden: Bool
    let isImported: Bool
    let card: VauchiContactCard
    let addedAt: UInt64
    let trustLevel: MobileContactTrustLevel
    let proposalTrusted: Bool
    let reciprocity: MobileReciprocity
}

// MARK: - Visibility Label Types

// Based on: features/visibility_labels.feature

/// Visibility label for organizing contacts
struct VauchiVisibilityLabel: Identifiable {
    let id: String
    let name: String
    let contactCount: UInt32
    let visibleFieldCount: UInt32
    let createdAt: UInt64
    let modifiedAt: UInt64

    init(
        id: String,
        name: String,
        contactCount: UInt32,
        visibleFieldCount: UInt32,
        createdAt: UInt64,
        modifiedAt: UInt64
    ) {
        self.id = id
        self.name = name
        self.contactCount = contactCount
        self.visibleFieldCount = visibleFieldCount
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from mobile: MobileVisibilityLabel) {
        self.init(
            id: mobile.id,
            name: mobile.name,
            contactCount: mobile.contactCount,
            visibleFieldCount: mobile.visibleFieldCount,
            createdAt: mobile.createdAt,
            modifiedAt: mobile.modifiedAt
        )
    }
}

/// Detailed visibility label including contacts and fields
struct VauchiVisibilityLabelDetail: Identifiable {
    let id: String
    let name: String
    let contactIds: [String]
    let visibleFieldIds: [String]
    let createdAt: UInt64
    let modifiedAt: UInt64

    init(from mobile: MobileVisibilityLabelDetail) {
        id = mobile.id
        name = mobile.name
        contactIds = mobile.contactIds
        visibleFieldIds = mobile.visibleFieldIds
        createdAt = mobile.createdAt
        modifiedAt = mobile.modifiedAt
    }
}

/// Social network info
struct VauchiSocialNetwork: Identifiable {
    let id: String
    let displayName: String
    let urlTemplate: String
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

    // MARK: - Type Conversion Helpers

    private func convertField(_ field: MobileContactField) -> VauchiContactField {
        VauchiContactField(
            id: field.id,
            fieldType: VauchiFieldType.from(field.fieldType),
            label: field.label,
            value: field.value
        )
    }

    private func convertCard(_ card: MobileContactCard) -> VauchiContactCard {
        VauchiContactCard(
            displayName: card.displayName,
            fields: card.fields.map(convertField)
        )
    }

    private func convertContact(_ contact: MobileContact) -> VauchiContact {
        VauchiContact(
            id: contact.id,
            displayName: contact.displayName,
            fingerprint: contact.fingerprint,
            isVerified: contact.isVerified,
            isRecoveryTrusted: contact.isRecoveryTrusted,
            isHidden: contact.isHidden,
            isImported: contact.isImported,
            card: convertCard(contact.card),
            addedAt: contact.addedAt,
            trustLevel: contact.trustLevel,
            proposalTrusted: contact.proposalTrusted,
            reciprocity: contact.reciprocity
        )
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

    /// Get public ID
    func getPublicId() throws -> String {
        do {
            return try appEngine.getPublicId()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get display name
    func getDisplayName() throws -> String {
        do {
            return try appEngine.getDisplayName()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Card Operations

    /// Get own contact card
    func getOwnCard() throws -> VauchiContactCard {
        do {
            let card = try appEngine.getOwnCard()
            return convertCard(card)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Add field to own card
    func addField(type: VauchiFieldType, label: String, value: String) throws {
        do {
            try appEngine.addField(fieldType: type.toMobile, label: label, value: value)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Update field value
    func updateField(label: String, newValue: String) throws {
        do {
            try appEngine.updateField(label: label, newValue: newValue)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Remove field by label
    func removeField(label: String) throws -> Bool {
        do {
            return try appEngine.removeField(label: label)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Set display name
    func setDisplayName(_ name: String) throws {
        do {
            try appEngine.setDisplayName(name: name)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Contact Operations

    /// List all contacts
    func listContacts() throws -> [VauchiContact] {
        do {
            return try appEngine.listContacts().map(convertContact)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get contact by ID
    func getContact(id: String) throws -> VauchiContact? {
        do {
            return try appEngine.getContact(id: id).map(convertContact)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Search contacts
    func searchContacts(query: String) throws -> [VauchiContact] {
        do {
            return try appEngine.searchContacts(query: query).map(convertContact)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get contact count
    func contactCount() throws -> UInt32 {
        do {
            return try appEngine.contactCount()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Contact Lifecycle (reversible deletion + archival)

    // MARK: - Hidden Contacts Operations

    // Based on: features/resistance.feature - R3 Hidden Contact UI

    // MARK: - Duress PIN Operations

    // Based on: features/duress_pin.feature - R1 Duress PIN

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

    // MARK: - Decoy Contacts (duress mode profile)

    // Emergency Broadcast Operations (R5 / features/emergency_broadcast.feature)
    // — the 4 PAE delegators (`configureEmergencyBroadcast`,
    // `getEmergencyConfig`, `sendEmergencyBroadcast`,
    // `disableEmergencyBroadcast`) were retired 2026-05-23 (Track A
    // orphan cleanup): no view, model, or service called them in `ios/`.
    // The R5 UI surface routes through core engines / `dispatchDomainCommand`
    // when wired; when it lands the wrappers can return without re-shipping
    // the dead orphans first.

    // MARK: - Visibility Operations

    // MARK: - Visibility Labels Operations

    // Based on: features/visibility_labels.feature

    /// List all visibility labels
    func listLabels() throws -> [VauchiVisibilityLabel] {
        do {
            return try appEngine.listLabels().map { VauchiVisibilityLabel(from: $0) }
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Create a new visibility label
    func createLabel(name: String) throws -> VauchiVisibilityLabel {
        do {
            let label = try appEngine.createLabel(name: name)
            return VauchiVisibilityLabel(from: label)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get label details by ID
    func getLabel(id: String) throws -> VauchiVisibilityLabelDetail {
        do {
            let detail = try appEngine.getLabel(labelId: id)
            return VauchiVisibilityLabelDetail(from: detail)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Rename a visibility label
    func renameLabel(id: String, newName: String) throws {
        do {
            try appEngine.renameLabel(labelId: id, newName: newName)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Delete a visibility label
    func deleteLabel(id: String) throws {
        do {
            try appEngine.deleteLabel(labelId: id)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Add contact to a label
    func addContactToLabel(labelId: String, contactId: String) throws {
        do {
            try appEngine.addContactToGroup(labelId: labelId, contactId: contactId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Set field visibility for a label
    func setLabelFieldVisibility(labelId: String, fieldLabel: String, isVisible: Bool) throws {
        do {
            try appEngine.setGroupFieldVisibility(labelId: labelId, fieldLabel: fieldLabel, isVisible: isVisible)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get suggested label names.
    ///
    /// Non-throwing wrapper that returns `[]` on failure — `getSuggestedLabels`
    /// is a non-essential UI hint, so dispatch errors silently degrade rather
    /// than propagate. The legacy `vauchi.getSuggestedLabels()` was likewise
    /// non-throwing on the FFI surface; we preserve that shape.
    func getSuggestedLabels() -> [String] {
        (try? appEngine.getSuggestedLabels()) ?? []
    }

    // MARK: - Exchange Operations

    // QR-manual exchange — the session-based `generateExchangeQrWithSession`
    // / `finalizeExchange(session:)` wrappers + `ExchangeSessionData` +
    // `ExchangeCommandHandler` were retired by slice 32m (2026-05-29):
    // orphaned (no live view caller; `ExchangeCommandHandler` never
    // instantiated). Exchange is engine-owned — the frontend renders the
    // CoreUI screen and routes commands via `handleExchangeCommands`
    // (`ActionResult`/pending-commands envelope), same as multi-stage.

    // Multi-stage exchange — the `createMultistageSession` Repository
    // wrapper was retired 2026-05-23 (Track A orphan cleanup): no view,
    // model, or service called it. The link-mode responder is now
    // engine-owned (core AppEngine); the frontend renders the screen
    // and routes RelayEscrow* via the standard command envelope.

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

    // MARK: - Backup Operations

    /// Export encrypted backup
    func exportBackup(password: String) throws -> String {
        do {
            return try appEngine.exportBackup(password: password)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Import backup
    func importBackup(data: String, password: String) throws {
        do {
            try appEngine.importBackup(backupData: data, password: password)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Social Networks

    /// List available social networks.
    ///
    /// Non-throwing wrapper that returns `[]` on dispatch failure — the
    /// callers treat social-networks data as a UI hint, so silent
    /// degradation matches the legacy `vauchi.listSocialNetworks()`
    /// shape. Same convention applies to the other Social/Content/
    /// Aha/Cert wrappers below where the legacy FFI was non-throwing.
    func listSocialNetworks() -> [VauchiSocialNetwork] {
        ((try? appEngine.listSocialNetworks()) ?? []).map { sn in
            VauchiSocialNetwork(
                id: sn.id,
                displayName: sn.displayName,
                urlTemplate: sn.urlTemplate
            )
        }
    }

    /// Get profile URL for social network
    func getProfileUrl(networkId: String, username: String) -> String? {
        (try? appEngine.getProfileUrl(networkId: networkId, username: username)) ?? nil
    }

    // MARK: - Certificate Pinning

    // MARK: - Recovery Operations

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

    /// Get the current demo contact if active.
    ///
    /// - Returns: The demo contact if active, nil otherwise
    func getDemoContact() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try appEngine.getDemoContact() else {
                return nil
            }
            return VauchiDemoContact(from: mobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the demo contact state.
    ///
    /// Non-throwing wrapper — falls back to an inactive default on
    /// dispatch failure to match the legacy non-throwing
    /// `vauchi.getDemoContactState()` shape.
    ///
    /// - Returns: Current state of the demo contact
    func getDemoContactState() -> VauchiDemoContactState {
        let fallback = MobileDemoContactState(
            isActive: false,
            wasDismissed: false,
            autoRemoved: false,
            updateCount: 0
        )
        let mobile = (try? appEngine.getDemoContactState()) ?? fallback
        return VauchiDemoContactState(from: mobile)
    }

    /// Check if a demo update is available.
    ///
    /// - Returns: True if an update is due (based on 2-hour interval)
    func isDemoUpdateAvailable() -> Bool {
        (try? appEngine.isDemoUpdateAvailable()) ?? false
    }

    /// Trigger a demo update and get the new content.
    ///
    /// - Returns: Updated demo contact with new tip, nil if demo not active
    func triggerDemoUpdate() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try appEngine.triggerDemoUpdate() else {
                return nil
            }
            return VauchiDemoContact(from: mobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Dismiss the demo contact manually.
    func dismissDemoContact() throws {
        do {
            try appEngine.dismissDemoContact()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Restore the demo contact from Settings.
    ///
    /// - Returns: The restored demo contact
    func restoreDemoContact() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try appEngine.restoreDemoContact() else {
                return nil
            }
            return VauchiDemoContact(from: mobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - GDPR Operations
}

// MARK: - GDPR Types

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

/// State of the demo contact
struct VauchiDemoContactState {
    /// Whether the demo contact is currently active
    let isActive: Bool
    /// Whether it was manually dismissed by the user
    let wasDismissed: Bool
    /// Whether it was auto-removed after first real exchange
    let autoRemoved: Bool
    /// Number of updates that have been shown
    let updateCount: UInt32

    init(from mobile: MobileDemoContactState) {
        isActive = mobile.isActive
        wasDismissed = mobile.wasDismissed
        autoRemoved = mobile.autoRemoved
        updateCount = mobile.updateCount
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
