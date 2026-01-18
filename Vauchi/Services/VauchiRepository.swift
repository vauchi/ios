// VauchiRepository.swift
// Repository layer wrapping UniFFI bindings for Vauchi iOS

import Foundation

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

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Library not initialized"
        case .alreadyInitialized:
            return "Already initialized"
        case .identityNotFound:
            return "Identity not found"
        case .contactNotFound(let id):
            return "Contact not found: \(id)"
        case .invalidQrCode:
            return "Invalid QR code"
        case .exchangeFailed(let msg):
            return "Exchange failed: \(msg)"
        case .syncFailed(let msg):
            return "Sync failed: \(msg)"
        case .storageError(let msg):
            return "Storage error: \(msg)"
        case .cryptoError(let msg):
            return "Crypto error: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .internalError(let msg):
            return "Internal error: \(msg)"
        }
    }

    /// Convert from MobileError to VauchiRepositoryError
    static func from(_ error: MobileError) -> VauchiRepositoryError {
        switch error {
        case .NotInitialized:
            return .notInitialized
        case .AlreadyInitialized:
            return .alreadyInitialized
        case .IdentityNotFound:
            return .identityNotFound
        case .ContactNotFound(let id):
            return .contactNotFound(id)
        case .InvalidQrCode:
            return .invalidQrCode
        case .ExchangeFailed(let msg):
            return .exchangeFailed(msg)
        case .SyncFailed(let msg):
            return .syncFailed(msg)
        case .StorageError(let msg):
            return .storageError(msg)
        case .CryptoError(let msg):
            return .cryptoError(msg)
        case .NetworkError(let msg):
            return .networkError(msg)
        case .InvalidInput(let msg):
            return .invalidInput(msg)
        case .SerializationError(let msg):
            return .internalError("Serialization: \(msg)")
        case .Internal(let msg):
            return .internalError(msg)
        }
    }
}

/// Sync status enum
enum VauchiSyncStatus {
    case idle
    case syncing
    case error
}

/// Sync result
struct VauchiSyncResult {
    let contactsAdded: UInt32
    let cardsUpdated: UInt32
    let updatesSent: UInt32
}

/// Field type enum matching Rust MobileFieldType
enum VauchiFieldType: String, CaseIterable {
    case email = "email"
    case phone = "phone"
    case website = "website"
    case address = "address"
    case social = "social"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .email: return "Email"
        case .phone: return "Phone"
        case .website: return "Website"
        case .address: return "Address"
        case .social: return "Social"
        case .custom: return "Custom"
        }
    }

    /// Convert to MobileFieldType
    var toMobile: MobileFieldType {
        switch self {
        case .email: return .email
        case .phone: return .phone
        case .website: return .website
        case .address: return .address
        case .social: return .social
        case .custom: return .custom
        }
    }

    /// Convert from MobileFieldType
    static func from(_ mobile: MobileFieldType) -> VauchiFieldType {
        switch mobile {
        case .email: return .email
        case .phone: return .phone
        case .website: return .website
        case .address: return .address
        case .social: return .social
        case .custom: return .custom
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
    let isVerified: Bool
    let card: VauchiContactCard
    let addedAt: UInt64
}

/// Exchange data for QR code generation
struct VauchiExchangeData {
    let qrData: String
    let publicId: String
    let expiresAt: UInt64

    var isExpired: Bool {
        UInt64(Date().timeIntervalSince1970) > expiresAt
    }

    var timeRemaining: TimeInterval {
        let now = Date().timeIntervalSince1970
        return max(0, Double(expiresAt) - now)
    }
}

/// Exchange result
struct VauchiExchangeResult {
    let contactId: String
    let contactName: String
    let success: Bool
    let errorMessage: String?
}

/// Social network info
struct VauchiSocialNetwork: Identifiable {
    let id: String
    let displayName: String
    let urlTemplate: String
}

/// Repository class wrapping VauchiMobile UniFFI bindings
class VauchiRepository {
    // MARK: - Properties

    private let vauchi: VauchiMobile
    private let dataDir: String
    private let relayUrl: String
    private static let storageKeyLength = 32  // 256-bit key

    // MARK: - Initialization

    /// Initialize repository with data directory and relay URL
    /// Uses iOS Keychain for secure storage key management
    init(dataDir: String? = nil, relayUrl: String = "wss://relay.vauchi.app") throws {
        let dir = dataDir ?? VauchiRepository.defaultDataDir()
        self.dataDir = dir
        self.relayUrl = relayUrl

        // Create data directory if needed
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Get storage key from Keychain (or migrate/generate)
        let storageKeyBytes = try VauchiRepository.getOrCreateStorageKey(dataDir: dir)

        // Initialize VauchiMobile with secure key from Keychain
        do {
            self.vauchi = try VauchiMobile.newWithSecureKey(
                dataDir: dir,
                relayUrl: relayUrl,
                storageKeyBytes: storageKeyBytes
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Default data directory in Application Support
    static func defaultDataDir() -> String {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Vauchi")
        return appSupport.path
    }

    // MARK: - Secure Key Management

    /// Get or create storage key from Keychain
    /// Handles migration from legacy file-based key storage
    private static func getOrCreateStorageKey(dataDir: String) throws -> [UInt8] {
        let keychain = KeychainService.shared
        let legacyKeyPath = (dataDir as NSString).appendingPathComponent("storage.key")

        // Try to load from Keychain first
        if let keyData = try? keychain.loadStorageKey() {
            if keyData.count == storageKeyLength {
                return Array(keyData)
            }
        }

        // Check for legacy file-based key (migration scenario)
        if FileManager.default.fileExists(atPath: legacyKeyPath) {
            // Load legacy key
            let legacyKeyData = try Data(contentsOf: URL(fileURLWithPath: legacyKeyPath))
            if legacyKeyData.count == storageKeyLength {
                // Migrate to Keychain
                try keychain.saveStorageKey(legacyKeyData)

                // Securely delete old file
                try FileManager.default.removeItem(atPath: legacyKeyPath)

                return Array(legacyKeyData)
            }
        }

        // Generate new key and store in Keychain
        let newKeyBytes = generateStorageKey()
        let newKeyData = Data(newKeyBytes)
        try keychain.saveStorageKey(newKeyData)

        return newKeyBytes
    }

    /// Export current storage key (for backup purposes only)
    /// WARNING: Handle the returned data with extreme care
    func exportStorageKey() -> [UInt8] {
        return vauchi.exportStorageKey()
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
            isVerified: contact.isVerified,
            card: convertCard(contact.card),
            addedAt: contact.addedAt
        )
    }

    // MARK: - Identity Operations

    /// Check if identity exists
    func hasIdentity() -> Bool {
        return vauchi.hasIdentity()
    }

    /// Create new identity with display name
    func createIdentity(displayName: String) throws {
        do {
            try vauchi.createIdentity(displayName: displayName)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get public ID
    func getPublicId() throws -> String {
        do {
            return try vauchi.getPublicId()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get display name
    func getDisplayName() throws -> String {
        do {
            return try vauchi.getDisplayName()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Card Operations

    /// Get own contact card
    func getOwnCard() throws -> VauchiContactCard {
        do {
            let card = try vauchi.getOwnCard()
            return convertCard(card)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Add field to own card
    func addField(type: VauchiFieldType, label: String, value: String) throws {
        do {
            try vauchi.addField(fieldType: type.toMobile, label: label, value: value)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Update field value
    func updateField(label: String, newValue: String) throws {
        do {
            try vauchi.updateField(label: label, newValue: newValue)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Remove field by label
    func removeField(label: String) throws -> Bool {
        do {
            return try vauchi.removeField(label: label)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Set display name
    func setDisplayName(_ name: String) throws {
        do {
            try vauchi.setDisplayName(name: name)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Contact Operations

    /// List all contacts
    func listContacts() throws -> [VauchiContact] {
        do {
            return try vauchi.listContacts().map(convertContact)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get contact by ID
    func getContact(id: String) throws -> VauchiContact? {
        do {
            return try vauchi.getContact(id: id).map(convertContact)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Search contacts
    func searchContacts(query: String) throws -> [VauchiContact] {
        do {
            return try vauchi.searchContacts(query: query).map(convertContact)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get contact count
    func contactCount() throws -> UInt32 {
        do {
            return try vauchi.contactCount()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Remove contact
    func removeContact(id: String) throws -> Bool {
        do {
            return try vauchi.removeContact(id: id)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Verify contact fingerprint
    func verifyContact(id: String) throws {
        do {
            try vauchi.verifyContact(id: id)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Visibility Operations

    /// Hide field from contact
    func hideFieldFromContact(contactId: String, fieldLabel: String) throws {
        do {
            try vauchi.hideFieldFromContact(contactId: contactId, fieldLabel: fieldLabel)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Show field to contact
    func showFieldToContact(contactId: String, fieldLabel: String) throws {
        do {
            try vauchi.showFieldToContact(contactId: contactId, fieldLabel: fieldLabel)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Check if field is visible to contact
    func isFieldVisibleToContact(contactId: String, fieldLabel: String) throws -> Bool {
        do {
            return try vauchi.isFieldVisibleToContact(contactId: contactId, fieldLabel: fieldLabel)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Exchange Operations

    /// Generate QR data for exchange
    func generateExchangeQr() throws -> VauchiExchangeData {
        do {
            let data = try vauchi.generateExchangeQr()
            return VauchiExchangeData(
                qrData: data.qrData,
                publicId: data.publicId,
                expiresAt: data.expiresAt
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Complete exchange with scanned QR data
    func completeExchange(qrData: String) throws -> VauchiExchangeResult {
        do {
            let result = try vauchi.completeExchange(qrData: qrData)
            return VauchiExchangeResult(
                contactId: result.contactId,
                contactName: result.contactName,
                success: result.success,
                errorMessage: result.errorMessage
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Sync Operations

    /// Sync with relay server
    func sync() throws -> VauchiSyncResult {
        do {
            let result = try vauchi.sync()
            return VauchiSyncResult(
                contactsAdded: result.contactsAdded,
                cardsUpdated: result.cardsUpdated,
                updatesSent: result.updatesSent
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get sync status
    func getSyncStatus() -> VauchiSyncStatus {
        switch vauchi.getSyncStatus() {
        case .idle: return .idle
        case .syncing: return .syncing
        case .error: return .error
        }
    }

    /// Get pending update count
    func pendingUpdateCount() throws -> UInt32 {
        do {
            return try vauchi.pendingUpdateCount()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Backup Operations

    /// Export encrypted backup
    func exportBackup(password: String) throws -> String {
        do {
            return try vauchi.exportBackup(password: password)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Import backup
    func importBackup(data: String, password: String) throws {
        do {
            try vauchi.importBackup(backupData: data, password: password)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Social Networks

    /// List available social networks
    func listSocialNetworks() -> [VauchiSocialNetwork] {
        return vauchi.listSocialNetworks().map { sn in
            VauchiSocialNetwork(
                id: sn.id,
                displayName: sn.displayName,
                urlTemplate: sn.urlTemplate
            )
        }
    }

    /// Search social networks
    func searchSocialNetworks(query: String) -> [VauchiSocialNetwork] {
        return vauchi.searchSocialNetworks(query: query).map { sn in
            VauchiSocialNetwork(
                id: sn.id,
                displayName: sn.displayName,
                urlTemplate: sn.urlTemplate
            )
        }
    }

    /// Get profile URL for social network
    func getProfileUrl(networkId: String, username: String) -> String? {
        return vauchi.getProfileUrl(networkId: networkId, username: username)
    }

    // MARK: - Recovery Operations

    /// Recovery claim info
    struct RecoveryClaimInfo {
        let oldPublicKey: String
        let newPublicKey: String
        let claimData: String
        let isExpired: Bool
    }

    /// Recovery voucher info
    struct RecoveryVoucherInfo {
        let voucherPublicKey: String
        let voucherData: String
    }

    /// Recovery progress info
    struct RecoveryProgressInfo {
        let oldPublicKey: String
        let newPublicKey: String
        let vouchersCollected: UInt32
        let vouchersNeeded: UInt32
        let isComplete: Bool
    }

    /// Create a recovery claim for a lost identity
    func createRecoveryClaim(oldPkHex: String) throws -> RecoveryClaimInfo {
        do {
            let claim = try vauchi.createRecoveryClaim(oldPkHex: oldPkHex)
            return RecoveryClaimInfo(
                oldPublicKey: claim.oldPublicKey,
                newPublicKey: claim.newPublicKey,
                claimData: claim.claimData,
                isExpired: claim.isExpired
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Parse a recovery claim from base64
    func parseRecoveryClaim(claimB64: String) throws -> RecoveryClaimInfo {
        do {
            let claim = try vauchi.parseRecoveryClaim(claimB64: claimB64)
            return RecoveryClaimInfo(
                oldPublicKey: claim.oldPublicKey,
                newPublicKey: claim.newPublicKey,
                claimData: claim.claimData,
                isExpired: claim.isExpired
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Create a voucher for someone's recovery claim
    func createRecoveryVoucher(claimB64: String) throws -> RecoveryVoucherInfo {
        do {
            let voucher = try vauchi.createRecoveryVoucher(claimB64: claimB64)
            return RecoveryVoucherInfo(
                voucherPublicKey: voucher.voucherPublicKey,
                voucherData: voucher.voucherData
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Add a voucher to the current recovery claim
    func addRecoveryVoucher(voucherB64: String) throws -> RecoveryProgressInfo {
        do {
            let progress = try vauchi.addRecoveryVoucher(voucherB64: voucherB64)
            return RecoveryProgressInfo(
                oldPublicKey: progress.oldPublicKey,
                newPublicKey: progress.newPublicKey,
                vouchersCollected: progress.vouchersCollected,
                vouchersNeeded: progress.vouchersNeeded,
                isComplete: progress.isComplete
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the current recovery progress
    func getRecoveryStatus() throws -> RecoveryProgressInfo? {
        do {
            guard let progress = try vauchi.getRecoveryStatus() else {
                return nil
            }
            return RecoveryProgressInfo(
                oldPublicKey: progress.oldPublicKey,
                newPublicKey: progress.newPublicKey,
                vouchersCollected: progress.vouchersCollected,
                vouchersNeeded: progress.vouchersNeeded,
                isComplete: progress.isComplete
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the completed recovery proof as base64
    func getRecoveryProof() throws -> String? {
        do {
            return try vauchi.getRecoveryProof()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }
}
