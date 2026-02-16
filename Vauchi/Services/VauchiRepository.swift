// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiRepository.swift
// Repository layer wrapping UniFFI bindings for Vauchi iOS
//
// DONE: Restore feature - RestoreIdentitySheet in OnboardingView.swift allows users
// to restore from backup during onboarding using importBackup().
//
// DONE: Proximity verification - MobileProximityVerifier enabled in VauchiViewModel.swift
// with AudioProximityService providing platform audio. Exposes emitProximityChallenge(),
// listenForProximityResponse(), stopProximityVerification(), proximitySupported, proximityCapability.
//
// DONE: Content updates - isContentUpdatesSupported(), checkContentUpdates(),
// applyContentUpdates(), reloadSocialNetworks() methods implemented.
//
// DONE: Field validation - validateField(), getFieldValidationStatus(),
// revokeFieldValidation(), listMyValidations(), hasValidatedField(),
// getFieldValidationCount() methods implemented.
//
// DONE: Password strength indicator - checkPasswordStrength() integrated in ExportBackupSheet
// with PasswordStrengthIndicator component showing real-time visual feedback.
//
// DONE: Aha moments - hasSeenAhaMoment(), tryTriggerAhaMoment(),
// tryTriggerAhaMomentWithContext(), ahaMomentsSeenCount(), ahaMomentsTotalCount(),
// resetAhaMoments() methods implemented for progressive onboarding hints.
//
// DONE: Demo contact - implemented initDemoContactIfNeeded(), getDemoContact(),
// getDemoContactState(), isDemoUpdateAvailable(), triggerDemoUpdate(),
// dismissDemoContact(), autoRemoveDemoContact(), restoreDemoContact().
//
// DONE: Device linking - getDevices(), generateDeviceLinkQr(), parseDeviceLinkQr(),
// deviceCount(), unlinkDevice(), isPrimaryDevice() methods implemented.
//
// DONE: Certificate pinning UI - isCertificatePinningEnabled(), setPinnedCertificate()
// methods implemented. UI added to Settings under Security section.

import Foundation
import VauchiMobile

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

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Library not initialized"
        case .alreadyInitialized:
            return "Already initialized"
        case .identityNotFound:
            return "Identity not found"
        case let .contactNotFound(id):
            return "Contact not found: \(id)"
        case .invalidQrCode:
            return "Invalid QR code"
        case let .exchangeFailed(msg):
            return "Exchange failed: \(msg)"
        case let .syncFailed(msg):
            return "Sync failed: \(msg)"
        case let .storageError(msg):
            return "Storage error: \(msg)"
        case let .cryptoError(msg):
            return "Crypto error: \(msg)"
        case let .networkError(msg):
            return "Network error: \(msg)"
        case let .invalidInput(msg):
            return "Invalid input: \(msg)"
        case let .internalError(msg):
            return "Internal error: \(msg)"
        case let .gdprError(msg):
            return "GDPR error: \(msg)"
        case let .deletionNotAllowed(msg):
            return "Deletion not allowed: \(msg)"
        case let .shredError(msg):
            return "Shred error: \(msg)"
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
        case let .ContactNotFound(id):
            return .contactNotFound(id)
        case .InvalidQrCode:
            return .invalidQrCode
        case let .ExchangeFailed(msg):
            return .exchangeFailed(msg)
        case let .SyncFailed(msg):
            return .syncFailed(msg)
        case let .StorageError(msg):
            return .storageError(msg)
        case let .CryptoError(msg):
            return .cryptoError(msg)
        case let .NetworkError(msg):
            return .networkError(msg)
        case let .InvalidInput(msg):
            return .invalidInput(msg)
        case let .SerializationError(msg):
            return .internalError("Serialization: \(msg)")
        case let .Internal(msg):
            return .internalError(msg)
        case let .GdprError(msg):
            return .gdprError(msg)
        case let .DeletionNotAllowed(msg):
            return .deletionNotAllowed(msg)
        case let .ShredError(msg):
            return .shredError(msg)
        @unknown default:
            return .internalError("Unknown error")
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
    case email
    case phone
    case website
    case address
    case social
    case custom

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
    let isRecoveryTrusted: Bool
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

    init(from mobile: MobileVisibilityLabel) {
        id = mobile.id
        name = mobile.name
        contactCount = mobile.contactCount
        visibleFieldCount = mobile.visibleFieldCount
        createdAt = mobile.createdAt
        modifiedAt = mobile.modifiedAt
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

// MARK: - Delivery Status Types

/// Delivery status for tracking message delivery
enum VauchiDeliveryStatus: Equatable {
    case queued
    case sent
    case stored
    case delivered
    case expired
    case failed(reason: String)

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .sent: return "Sent"
        case .stored: return "Stored"
        case .delivered: return "Delivered"
        case .expired: return "Expired"
        case .failed: return "Failed"
        }
    }

    var iconName: String {
        switch self {
        case .queued: return "clock"
        case .sent: return "arrow.up.circle"
        case .stored: return "checkmark.circle"
        case .delivered: return "checkmark.circle.fill"
        case .expired: return "exclamationmark.triangle"
        case .failed: return "xmark.circle"
        }
    }

    var color: String {
        switch self {
        case .queued: return "gray"
        case .sent: return "blue"
        case .stored: return "cyan"
        case .delivered: return "green"
        case .expired: return "orange"
        case .failed: return "red"
        }
    }

    /// Convert from MobileDeliveryStatus
    static func from(_ mobile: MobileDeliveryStatus) -> VauchiDeliveryStatus {
        switch mobile {
        case .queued: return .queued
        case .sent: return .sent
        case .stored: return .stored
        case .delivered: return .delivered
        case .expired: return .expired
        case .failed: return .failed(reason: "")
        }
    }
}

/// Delivery record for tracking outbound message status
struct VauchiDeliveryRecord: Identifiable {
    let id: String
    let messageId: String
    let recipientId: String
    let status: VauchiDeliveryStatus
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?

    init(messageId: String, recipientId: String, status: VauchiDeliveryStatus,
         createdAt: Date, updatedAt: Date, expiresAt: Date?)
    {
        id = messageId
        self.messageId = messageId
        self.recipientId = recipientId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

/// Retry entry for failed deliveries
struct VauchiRetryEntry: Identifiable {
    let id: String
    let messageId: String
    let recipientId: String
    let attempt: UInt32
    let nextRetry: Date
    let createdAt: Date
    let maxAttempts: UInt32

    var isMaxExceeded: Bool {
        attempt >= maxAttempts
    }
}

/// Summary of delivery status across all devices
struct VauchiDeliverySummary {
    let messageId: String
    let totalDevices: UInt32
    let deliveredDevices: UInt32
    let pendingDevices: UInt32
    let failedDevices: UInt32

    var isFullyDelivered: Bool {
        deliveredDevices == totalDevices && totalDevices > 0
    }

    var progressPercent: UInt32 {
        guard totalDevices > 0 else { return 0 }
        return (deliveredDevices * 100) / totalDevices
    }

    var displayText: String {
        "Delivered to \(deliveredDevices) of \(totalDevices) devices"
    }
}

/// Repository class wrapping VauchiMobile UniFFI bindings
class VauchiRepository {
    // MARK: - Properties

    private let vauchi: VauchiMobile
    private let dataDir: String
    private let relayUrl: String
    private static let storageKeyLength = 32 // 256-bit key

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
            vauchi = try VauchiMobile.newWithSecureKey(
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
    private static func getOrCreateStorageKey(dataDir _: String) throws -> Data {
        let keychain = KeychainService.shared

        // Try to load from Keychain first
        if let keyData = try? keychain.loadStorageKey() {
            if keyData.count == storageKeyLength {
                return keyData
            }
        }

        // Generate new key and store in Keychain
        let newKeyData = generateStorageKey()
        try keychain.saveStorageKey(newKeyData)

        return newKeyData
    }

    /// Export current storage key (for backup purposes only)
    /// WARNING: Handle the returned data with extreme care
    func exportStorageKey() -> Data {
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
            isRecoveryTrusted: contact.isRecoveryTrusted,
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

    /// List contacts with pagination
    func listContactsPaginated(offset: UInt32, limit: UInt32) throws -> [VauchiContact] {
        do {
            return try vauchi.listContactsPaginated(offset: offset, limit: limit).map(convertContact)
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

    // MARK: - Hidden Contacts Operations
    // Based on: features/resistance.feature - R3 Hidden Contact UI
    // NOTE: These methods are stubs until vauchi-core hidden contact bindings
    // are published via vauchi-mobile-swift. Once core MR !109 merges and
    // bindings are updated, replace stubs with actual UniFFI calls.

    /// Hide a contact
    func hideContact(id: String) throws {
        // TODO: Replace with `try vauchi.hideContact(id: id)` once bindings are published
        throw VauchiRepositoryError.internalError("Hidden contacts not yet available in bindings")
    }

    /// Unhide a contact
    func unhideContact(id: String) throws {
        // TODO: Replace with `try vauchi.unhideContact(id: id)` once bindings are published
        throw VauchiRepositoryError.internalError("Hidden contacts not yet available in bindings")
    }

    /// List hidden contacts
    func listHiddenContacts() throws -> [VauchiContact] {
        // TODO: Replace with `try vauchi.listHiddenContacts().map(convertContact)` once bindings are published
        throw VauchiRepositoryError.internalError("Hidden contacts not yet available in bindings")
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

    // MARK: - Visibility Labels Operations

    // Based on: features/visibility_labels.feature

    /// List all visibility labels
    func listLabels() throws -> [VauchiVisibilityLabel] {
        do {
            return try vauchi.listLabels().map { VauchiVisibilityLabel(from: $0) }
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Create a new visibility label
    func createLabel(name: String) throws -> VauchiVisibilityLabel {
        do {
            let label = try vauchi.createLabel(name: name)
            return VauchiVisibilityLabel(from: label)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get label details by ID
    func getLabel(id: String) throws -> VauchiVisibilityLabelDetail {
        do {
            let detail = try vauchi.getLabel(labelId: id)
            return VauchiVisibilityLabelDetail(from: detail)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Rename a visibility label
    func renameLabel(id: String, newName: String) throws {
        do {
            try vauchi.renameLabel(labelId: id, newName: newName)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Delete a visibility label
    func deleteLabel(id: String) throws {
        do {
            try vauchi.deleteLabel(labelId: id)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Add contact to a label
    func addContactToLabel(labelId: String, contactId: String) throws {
        do {
            try vauchi.addContactToLabel(labelId: labelId, contactId: contactId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Remove contact from a label
    func removeContactFromLabel(labelId: String, contactId: String) throws {
        do {
            try vauchi.removeContactFromLabel(labelId: labelId, contactId: contactId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get all labels for a contact
    func getLabelsForContact(contactId: String) throws -> [VauchiVisibilityLabel] {
        do {
            return try vauchi.getLabelsForContact(contactId: contactId).map { VauchiVisibilityLabel(from: $0) }
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Set field visibility for a label
    func setLabelFieldVisibility(labelId: String, fieldLabel: String, isVisible: Bool) throws {
        do {
            try vauchi.setLabelFieldVisibility(labelId: labelId, fieldLabel: fieldLabel, isVisible: isVisible)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get suggested label names
    func getSuggestedLabels() -> [String] {
        return vauchi.getSuggestedLabels()
    }

    // MARK: - Field Validation Operations

    // Based on: features/field_validation.feature

    /// Validate a contact's field
    func validateField(contactId: String, fieldId: String, fieldValue: String) throws -> MobileFieldValidation {
        do {
            return try vauchi.validateField(contactId: contactId, fieldId: fieldId, fieldValue: fieldValue)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get validation status for a contact's field
    func getFieldValidationStatus(contactId: String, fieldId: String, fieldValue: String) throws -> MobileValidationStatus {
        do {
            return try vauchi.getFieldValidationStatus(contactId: contactId, fieldId: fieldId, fieldValue: fieldValue)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Revoke your validation of a contact's field
    func revokeFieldValidation(contactId: String, fieldId: String) throws -> Bool {
        do {
            return try vauchi.revokeFieldValidation(contactId: contactId, fieldId: fieldId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// List all validations you have made
    func listMyValidations() throws -> [MobileFieldValidation] {
        do {
            return try vauchi.listMyValidations()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Check if you have validated a specific field
    func hasValidatedField(contactId: String, fieldId: String) throws -> Bool {
        do {
            return try vauchi.hasValidatedField(contactId: contactId, fieldId: fieldId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the validation count for a field
    func getFieldValidationCount(contactId: String, fieldId: String) throws -> UInt32 {
        do {
            return try vauchi.getFieldValidationCount(contactId: contactId, fieldId: fieldId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Exchange Operations

    /// Generate QR data for exchange using ExchangeSession state machine.
    func generateExchangeQr() throws -> VauchiExchangeData {
        do {
            let session = try vauchi.createQrExchangeManual()
            let qrData = try session.generateQr()
            let publicId = try vauchi.getPublicId()
            let expiresAt = UInt64(Date().timeIntervalSince1970) + 300 // 5 minutes
            return VauchiExchangeData(
                qrData: qrData,
                publicId: publicId,
                expiresAt: expiresAt
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Complete exchange by driving ExchangeSession state machine (mutual QR flow).
    func completeExchange(qrData: String) throws -> VauchiExchangeResult {
        do {
            let session = try vauchi.createQrExchangeManual()
            let _ = try session.generateQr()
            try session.processQr(qrData: qrData)
            try session.theyScannedOurQr()
            try session.performKeyAgreement()
            try session.completeCardExchange(theirCardName: "New Contact")
            let result = try vauchi.finalizeExchange(session: session)
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

    // MARK: - Content Updates

    // Based on: features/content_updates.feature

    /// Check if content updates feature is supported
    func isContentUpdatesSupported() -> Bool {
        return vauchi.isContentUpdatesSupported()
    }

    /// Check for available content updates
    func checkContentUpdates() -> MobileUpdateStatus {
        return vauchi.checkContentUpdates()
    }

    /// Apply available content updates
    func applyContentUpdates() -> MobileApplyResult {
        return vauchi.applyContentUpdates()
    }

    /// Reload social networks after content updates
    func reloadSocialNetworks() -> [VauchiSocialNetwork] {
        return vauchi.reloadSocialNetworks().map { sn in
            VauchiSocialNetwork(
                id: sn.id,
                displayName: sn.displayName,
                urlTemplate: sn.urlTemplate
            )
        }
    }

    // MARK: - Aha Moments (Progressive Onboarding)

    /// Check if user has seen a specific aha moment
    func hasSeenAhaMoment(_ momentType: MobileAhaMomentType) -> Bool {
        return vauchi.hasSeenAhaMoment(momentType: momentType)
    }

    /// Try to trigger an aha moment (returns nil if already seen)
    func tryTriggerAhaMoment(_ momentType: MobileAhaMomentType) throws -> MobileAhaMoment? {
        return try vauchi.tryTriggerAhaMoment(momentType: momentType)
    }

    /// Try to trigger an aha moment with context (returns nil if already seen)
    func tryTriggerAhaMomentWithContext(_ momentType: MobileAhaMomentType, context: String) throws -> MobileAhaMoment? {
        return try vauchi.tryTriggerAhaMomentWithContext(momentType: momentType, context: context)
    }

    /// Get count of seen aha moments
    func ahaMomentsSeenCount() -> UInt32 {
        return vauchi.ahaMomentsSeenCount()
    }

    /// Get total count of aha moments
    func ahaMomentsTotalCount() -> UInt32 {
        return vauchi.ahaMomentsTotalCount()
    }

    /// Reset all aha moments (for development/testing)
    func resetAhaMoments() throws {
        try vauchi.resetAhaMoments()
    }

    // MARK: - Certificate Pinning

    /// Check if certificate pinning is enabled
    func isCertificatePinningEnabled() -> Bool {
        return vauchi.isCertificatePinningEnabled()
    }

    /// Set the pinned certificate for relay TLS connections
    /// - Parameter certPem: Certificate in PEM format
    func setPinnedCertificate(_ certPem: String) {
        vauchi.setPinnedCertificate(certPem: certPem)
    }

    // MARK: - Device Linking Operations

    // Based on: features/device_linking.feature

    /// Device info for display
    struct DeviceInfo: Identifiable {
        let id: String
        let deviceIndex: UInt32
        let deviceName: String
        let isCurrent: Bool
        let isActive: Bool
        let publicKeyPrefix: String
        let createdAt: UInt64

        init(from mobile: MobileDeviceInfo) {
            id = mobile.publicKeyPrefix
            deviceIndex = mobile.deviceIndex
            deviceName = mobile.deviceName
            isCurrent = mobile.isCurrent
            isActive = mobile.isActive
            publicKeyPrefix = mobile.publicKeyPrefix
            createdAt = mobile.createdAt
        }
    }

    /// Device link QR data for display on existing device
    struct DeviceLinkData {
        let qrData: String
        let identityPublicKey: String
        let timestamp: UInt64
        let expiresAt: UInt64

        var isExpired: Bool {
            UInt64(Date().timeIntervalSince1970) > expiresAt
        }

        var timeRemaining: TimeInterval {
            let now = Date().timeIntervalSince1970
            return max(0, Double(expiresAt) - now)
        }

        init(from mobile: MobileDeviceLinkData) {
            qrData = mobile.qrData
            identityPublicKey = mobile.identityPublicKey
            timestamp = mobile.timestamp
            expiresAt = mobile.expiresAt
        }
    }

    /// Device link info parsed from QR code
    struct DeviceLinkInfo {
        let identityPublicKey: String
        let timestamp: UInt64
        let isExpired: Bool

        init(from mobile: MobileDeviceLinkInfo) {
            identityPublicKey = mobile.identityPublicKey
            timestamp = mobile.timestamp
            isExpired = mobile.isExpired
        }
    }

    /// Get list of linked devices
    func getDevices() throws -> [DeviceInfo] {
        do {
            return try vauchi.getDevices().map { DeviceInfo(from: $0) }
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Generate a device link QR code for a new device to scan
    func generateDeviceLinkQr() throws -> DeviceLinkData {
        do {
            let data = try vauchi.generateDeviceLinkQr()
            return DeviceLinkData(from: data)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Parse a device link QR code scanned from another device
    func parseDeviceLinkQr(qrData: String) throws -> DeviceLinkInfo {
        do {
            let info = try vauchi.parseDeviceLinkQr(qrData: qrData)
            return DeviceLinkInfo(from: info)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the number of linked devices
    func deviceCount() throws -> UInt32 {
        do {
            return try vauchi.deviceCount()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Unlink a device by its index in the device list
    /// - Parameter deviceIndex: The index of the device to unlink
    /// - Returns: True if the device was successfully unlinked
    func unlinkDevice(deviceIndex: UInt32) throws -> Bool {
        do {
            return try vauchi.unlinkDevice(deviceIndex: deviceIndex)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Check if this is the primary (first) device
    func isPrimaryDevice() throws -> Bool {
        do {
            return try vauchi.isPrimaryDevice()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
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

    /// Mark a contact as trusted for recovery
    func trustContactForRecovery(id: String) throws {
        do {
            try vauchi.trustContactForRecovery(id: id)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Remove recovery trust from a contact
    func untrustContactForRecovery(id: String) throws {
        do {
            try vauchi.untrustContactForRecovery(id: id)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the number of contacts trusted for recovery
    func trustedContactCount() throws -> UInt32 {
        do {
            return try vauchi.trustedContactCount()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Delivery Status Operations

    /// Get all delivery records
    func getAllDeliveryRecords() throws -> [VauchiDeliveryRecord] {
        do {
            return try vauchi.getAllDeliveryRecords().map(convertDeliveryRecord)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get delivery records for a specific contact
    func getDeliveryRecordsForContact(contactId: String) throws -> [VauchiDeliveryRecord] {
        do {
            return try vauchi.getDeliveryRecordsForContact(recipientId: contactId).map(convertDeliveryRecord)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get delivery summary for a message (multi-device)
    func getDeliverySummary(messageId: String) throws -> VauchiDeliverySummary {
        do {
            let summary = try vauchi.getDeliverySummary(messageId: messageId)
            return VauchiDeliverySummary(
                messageId: summary.messageId,
                totalDevices: summary.totalDevices,
                deliveredDevices: summary.deliveredDevices,
                pendingDevices: summary.pendingDevices,
                failedDevices: summary.failedDevices
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get all retry entries
    func getRetryEntries() throws -> [VauchiRetryEntry] {
        do {
            return try vauchi.getDueRetries().map(convertRetryEntry)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Retry a failed delivery
    func retryDelivery(messageId: String) throws -> Bool {
        do {
            return try vauchi.manualRetry(messageId: messageId)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get count of failed deliveries
    func failedDeliveryCount() throws -> UInt32 {
        do {
            return try vauchi.countFailedDeliveries()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - Delivery Type Conversion

    private func convertDeliveryRecord(_ record: MobileDeliveryRecord) -> VauchiDeliveryRecord {
        let status: VauchiDeliveryStatus
        switch record.status {
        case .queued: status = .queued
        case .sent: status = .sent
        case .stored: status = .stored
        case .delivered: status = .delivered
        case .expired: status = .expired
        case .failed: status = .failed(reason: record.errorReason ?? "Unknown error")
        }

        return VauchiDeliveryRecord(
            messageId: record.messageId,
            recipientId: record.recipientId,
            status: status,
            createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAt)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(record.updatedAt)),
            expiresAt: record.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func convertRetryEntry(_ entry: MobileRetryEntry) -> VauchiRetryEntry {
        VauchiRetryEntry(
            id: entry.messageId,
            messageId: entry.messageId,
            recipientId: entry.recipientId,
            attempt: entry.attempt,
            nextRetry: Date(timeIntervalSince1970: TimeInterval(entry.nextRetry)),
            createdAt: Date(timeIntervalSince1970: TimeInterval(entry.createdAt)),
            maxAttempts: entry.maxAttempts
        )
    }

    // MARK: - Demo Contact Operations

    // Based on: features/demo_contact.feature

    /// Initialize demo contact if user has no real contacts.
    /// Call this after onboarding completes.
    ///
    /// - Returns: The demo contact if created, nil if user has contacts or demo was dismissed
    func initDemoContactIfNeeded() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try vauchi.initDemoContactIfNeeded() else {
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
            guard let mobile = try vauchi.getDemoContact() else {
                return nil
            }
            return VauchiDemoContact(from: mobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get the demo contact state.
    ///
    /// - Returns: Current state of the demo contact
    func getDemoContactState() -> VauchiDemoContactState {
        let mobile = vauchi.getDemoContactState()
        return VauchiDemoContactState(from: mobile)
    }

    /// Check if a demo update is available.
    ///
    /// - Returns: True if an update is due (based on 2-hour interval)
    func isDemoUpdateAvailable() -> Bool {
        return vauchi.isDemoUpdateAvailable()
    }

    /// Trigger a demo update and get the new content.
    ///
    /// - Returns: Updated demo contact with new tip, nil if demo not active
    func triggerDemoUpdate() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try vauchi.triggerDemoUpdate() else {
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
            try vauchi.dismissDemoContact()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Auto-remove demo contact after first real exchange.
    /// Call this after a successful contact exchange.
    ///
    /// - Returns: True if demo was removed, false if it wasn't active
    func autoRemoveDemoContact() throws -> Bool {
        do {
            return try vauchi.autoRemoveDemoContact()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Restore the demo contact from Settings.
    ///
    /// - Returns: The restored demo contact
    func restoreDemoContact() throws -> VauchiDemoContact? {
        do {
            guard let mobile = try vauchi.restoreDemoContact() else {
                return nil
            }
            return VauchiDemoContact(from: mobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    // MARK: - GDPR Operations

    /// Export all user data in GDPR-compliant format
    func exportGdprData() throws -> VauchiGdprExport {
        do {
            let export = try vauchi.exportGdprData()
            return VauchiGdprExport(
                jsonData: export.jsonData,
                exportedAt: export.exportedAt,
                version: export.version
            )
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Schedule account deletion with grace period
    func scheduleAccountDeletion() throws -> VauchiDeletionInfo {
        do {
            let info = try vauchi.scheduleAccountDeletion()
            return VauchiDeletionInfo(from: info)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Cancel a scheduled account deletion
    func cancelAccountDeletion() throws {
        do {
            try vauchi.cancelAccountDeletion()
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get current deletion state
    func getDeletionState() throws -> VauchiDeletionInfo {
        do {
            let info = try vauchi.getDeletionState()
            return VauchiDeletionInfo(from: info)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Grant consent for a specific type
    func grantConsent(consentType: VauchiConsentType) throws {
        do {
            try vauchi.grantConsent(consentType: consentType.toMobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Revoke consent for a specific type
    func revokeConsent(consentType: VauchiConsentType) throws {
        do {
            try vauchi.revokeConsent(consentType: consentType.toMobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Check if consent is granted for a specific type
    func checkConsent(consentType: VauchiConsentType) throws -> Bool {
        do {
            return try vauchi.checkConsent(consentType: consentType.toMobile)
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }

    /// Get all consent records
    func getConsentRecords() throws -> [VauchiConsentRecord] {
        do {
            return try vauchi.getConsentRecords().map { VauchiConsentRecord(from: $0) }
        } catch let error as MobileError {
            throw VauchiRepositoryError.from(error)
        }
    }
}

// MARK: - GDPR Types

/// Deletion state enum matching MobileDeletionState
enum VauchiDeletionState {
    case none
    case scheduled
    case executed

    /// Convert from MobileDeletionState
    static func from(_ mobile: MobileDeletionState) -> VauchiDeletionState {
        switch mobile {
        case .none: return .none
        case .scheduled: return .scheduled
        case .executed: return .executed
        }
    }
}

/// GDPR data export result
struct VauchiGdprExport {
    let jsonData: String
    let exportedAt: UInt64
    let version: UInt32

    var exportedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(exportedAt))
    }
}

/// Consent type enum matching MobileConsentType
enum VauchiConsentType: String, CaseIterable {
    case dataProcessing
    case contactSharing
    case analytics
    case recoveryVouching

    var displayName: String {
        switch self {
        case .dataProcessing: return "Data Processing"
        case .contactSharing: return "Contact Sharing"
        case .analytics: return "Analytics"
        case .recoveryVouching: return "Recovery Vouching"
        }
    }

    /// Convert to MobileConsentType
    var toMobile: MobileConsentType {
        switch self {
        case .dataProcessing: return .dataProcessing
        case .contactSharing: return .contactSharing
        case .analytics: return .analytics
        case .recoveryVouching: return .recoveryVouching
        }
    }

    /// Convert from MobileConsentType
    static func from(_ mobile: MobileConsentType) -> VauchiConsentType {
        switch mobile {
        case .dataProcessing: return .dataProcessing
        case .contactSharing: return .contactSharing
        case .analytics: return .analytics
        case .recoveryVouching: return .recoveryVouching
        }
    }
}

/// Consent record
struct VauchiConsentRecord: Identifiable {
    let id: String
    let consentType: VauchiConsentType
    let granted: Bool
    let timestamp: UInt64
    let policyVersion: String?

    init(from mobile: MobileConsentRecord) {
        id = mobile.id
        consentType = VauchiConsentType.from(mobile.consentType)
        granted = mobile.granted
        timestamp = mobile.timestamp
        policyVersion = mobile.policyVersion
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

/// Deletion info containing state and timing
struct VauchiDeletionInfo {
    let state: VauchiDeletionState
    let scheduledAt: UInt64
    let executeAt: UInt64
    let daysRemaining: UInt32

    init(from mobile: MobileDeletionInfo) {
        state = VauchiDeletionState.from(mobile.state)
        scheduledAt = mobile.scheduledAt
        executeAt = mobile.executeAt
        daysRemaining = mobile.daysRemaining
    }

    var scheduledDate: Date {
        Date(timeIntervalSince1970: TimeInterval(scheduledAt))
    }

    var executeDate: Date {
        Date(timeIntervalSince1970: TimeInterval(executeAt))
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
