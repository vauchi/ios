// VauchiViewModel.swift
// Main state management for Vauchi iOS app

import Foundation
import SwiftUI
import Combine

/// Contact field for display
struct FieldInfo: Identifiable, Equatable {
    let id: String
    let fieldType: String
    let label: String
    let value: String
}

/// Contact card for display
struct CardInfo: Equatable {
    let displayName: String
    let fields: [FieldInfo]
}

/// Contact for display
struct ContactInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
    let verified: Bool
    let card: CardInfo?
    let addedAt: Date?

    init(id: String, displayName: String, verified: Bool, card: CardInfo? = nil, addedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.verified = verified
        self.card = card
        self.addedAt = addedAt
    }
}

/// Identity information
struct IdentityInfo: Equatable {
    let displayName: String
    let publicId: String
}

/// Exchange data for QR code display
struct ExchangeDataInfo: Equatable {
    let qrData: String
    let publicId: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
}

/// Exchange result after scanning QR
struct ExchangeResultInfo: Equatable {
    let contactId: String
    let contactName: String
    let success: Bool
    let errorMessage: String?
}

/// Sync state enum
enum SyncState: Equatable {
    case idle
    case syncing
    case success(contactsAdded: Int, cardsUpdated: Int, updatesSent: Int)
    case error(String)
}

/// Sync result
struct SyncResultInfo: Equatable {
    let contactsAdded: Int
    let cardsUpdated: Int
    let updatesSent: Int
}

@MainActor
class VauchiViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isLoading = true
    @Published var hasIdentity = false
    @Published var identity: IdentityInfo?
    @Published var card: CardInfo?
    @Published var contacts: [ContactInfo] = []
    @Published var errorMessage: String?
    @Published var syncState: SyncState = .idle
    @Published var lastSyncTime: Date?
    @Published var pendingUpdates: Int = 0

    // Network state
    @Published var isOnline = false

    // Delivery status
    @Published var deliveryRecords: [VauchiDeliveryRecord] = []
    @Published var retryEntries: [VauchiRetryEntry] = []
    @Published var failedDeliveryCount: Int = 0

    // Demo contact (for users with no contacts)
    @Published var demoContact: VauchiDemoContact?
    @Published var demoContactState: VauchiDemoContactState?

    // Visibility labels (for organizing contacts)
    // Based on: features/visibility_labels.feature
    @Published var visibilityLabels: [VauchiVisibilityLabel] = []
    @Published var suggestedLabels: [String] = []

    // User-facing alerts
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    /// Shows an error alert to the user
    func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    /// Shows a success alert to the user
    func showSuccess(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    // MARK: - Proximity Verification
    // Uses MobileProximityVerifier with AudioProximityService for ultrasonic verification

    @Published var proximitySupported = false
    @Published var proximityCapability = "none"
    private var proximityVerifier: MobileProximityVerifier?

    // Aha moments (progressive onboarding)
    @Published var currentAhaMoment: MobileAhaMoment?

    // MARK: - Private Properties

    private var repository: VauchiRepository?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        lastSyncTime = SettingsService.shared.lastSyncTime
        initializeRepository()
        setupNetworkMonitoring()
        setupProximityVerification()
    }

    private func setupProximityVerification() {
        let audioHandler = AudioProximityService.shared
        proximityVerifier = MobileProximityVerifier(handler: audioHandler)
        proximitySupported = proximityVerifier?.isSupported() ?? false
        proximityCapability = proximityVerifier?.getCapability() ?? "none"
        print("VauchiViewModel: Proximity verification enabled - capability: \(proximityCapability)")
    }

    /// Emit a proximity challenge (for QR displayer)
    func emitProximityChallenge(_ challenge: Data) -> Bool {
        guard let verifier = proximityVerifier, proximitySupported else {
            print("VauchiViewModel: Proximity verification not supported")
            return false
        }

        let result = verifier.emitChallenge(challenge: challenge)
        if !result.success {
            print("VauchiViewModel: emitProximityChallenge failed: \(result.error)")
        }
        return result.success
    }

    /// Listen for proximity response (for QR scanner)
    func listenForProximityResponse(timeoutMs: UInt64 = 5000) -> Data? {
        guard let verifier = proximityVerifier, proximitySupported else {
            print("VauchiViewModel: Proximity verification not supported")
            return nil
        }

        let response = verifier.listenForResponse(timeoutMs: timeoutMs)
        if response.isEmpty {
            return nil
        }
        return Data(response)
    }

    /// Stop any ongoing proximity verification
    func stopProximityVerification() {
        proximityVerifier?.stop()
    }

    private func initializeRepository() {
        do {
            print("VauchiViewModel: initializing repository...")
            repository = try VauchiRepository(
                relayUrl: SettingsService.shared.relayUrl
            )
            print("VauchiViewModel: repository initialized successfully")
        } catch {
            let msg = "Failed to initialize: \(error.localizedDescription) (\(String(describing: error)))"
            print("VauchiViewModel: \(msg)")
            errorMessage = msg
        }
    }

    private func setupNetworkMonitoring() {
        // Subscribe to network connectivity changes
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected

                // Auto-sync when connection restored (if enabled and has identity)
                if isConnected && SettingsService.shared.autoSyncEnabled && (self?.hasIdentity ?? false) {
                    Task {
                        await self?.sync()
                    }
                }
            }
            .store(in: &cancellables)

        // Initialize with current state
        isOnline = NetworkMonitor.shared.isConnected
    }

    // MARK: - State Management

    func loadState() {
        // Don't clear error if repository failed to initialize
        if repository == nil && errorMessage != nil {
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            hasIdentity = repository?.hasIdentity() ?? false

            if hasIdentity {
                await loadIdentity()
                await loadCard()
                await loadContacts()
                await loadPendingUpdates()
                await loadDemoContact()
            }

            isLoading = false
        }
    }

    // MARK: - Identity

    func createIdentity(name: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.createIdentity(displayName: name)
        hasIdentity = true

        // Load the created identity and card
        await loadIdentity()
        await loadCard()

        // Initialize demo contact for new users with no contacts
        await initDemoContactIfNeeded()
    }

    private func loadIdentity() async {
        guard let repository = repository else { return }

        do {
            let displayName = try repository.getDisplayName()
            let publicId = try repository.getPublicId()
            identity = IdentityInfo(displayName: displayName, publicId: publicId)
        } catch {
            // Identity not found is expected if not created yet
            identity = nil
        }
    }

    // MARK: - Card

    func loadCard() async {
        guard let repository = repository else { return }

        do {
            let cardData = try repository.getOwnCard()
            card = CardInfo(
                displayName: cardData.displayName,
                fields: cardData.fields.map { field in
                    FieldInfo(
                        id: field.id,
                        fieldType: field.fieldType.rawValue,
                        label: field.label,
                        value: field.value
                    )
                }
            )
        } catch {
            // Card not found is expected if identity not created
            card = nil
        }
    }

    func addField(type: String, label: String, value: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let fieldType = VauchiFieldType(rawValue: type) ?? .custom
        try repository.addField(type: fieldType, label: label, value: value)
        await loadCard()
    }

    func updateField(label: String, newValue: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.updateField(label: label, newValue: newValue)
        await loadCard()
    }

    func removeField(id: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        // Find field by ID to get its label
        guard let field = card?.fields.first(where: { $0.id == id }) else {
            return
        }

        _ = try repository.removeField(label: field.label)
        await loadCard()
    }

    func setDisplayName(_ name: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.setDisplayName(name)
        await loadIdentity()
        await loadCard()
    }

    // MARK: - Contacts

    func loadContacts() async {
        guard let repository = repository else { return }

        do {
            let contactsData = try repository.listContacts()
            contacts = contactsData.map { contact in
                ContactInfo(
                    id: contact.id,
                    displayName: contact.displayName,
                    verified: contact.isVerified,
                    card: CardInfo(
                        displayName: contact.card.displayName,
                        fields: contact.card.fields.map { field in
                            FieldInfo(
                                id: field.id,
                                fieldType: field.fieldType.rawValue,
                                label: field.label,
                                value: field.value
                            )
                        }
                    ),
                    addedAt: Date(timeIntervalSince1970: TimeInterval(contact.addedAt))
                )
            }
        } catch {
            contacts = []
        }
    }

    func getContact(id: String) async -> ContactInfo? {
        guard let repository = repository else { return nil }

        do {
            guard let contact = try repository.getContact(id: id) else {
                return nil
            }

            return ContactInfo(
                id: contact.id,
                displayName: contact.displayName,
                verified: contact.isVerified,
                card: CardInfo(
                    displayName: contact.card.displayName,
                    fields: contact.card.fields.map { field in
                        FieldInfo(
                            id: field.id,
                            fieldType: field.fieldType.rawValue,
                            label: field.label,
                            value: field.value
                        )
                    }
                ),
                addedAt: Date(timeIntervalSince1970: TimeInterval(contact.addedAt))
            )
        } catch {
            return nil
        }
    }

    func searchContacts(query: String) async -> [ContactInfo] {
        guard let repository = repository else { return [] }

        do {
            let results = try repository.searchContacts(query: query)
            return results.map { contact in
                ContactInfo(
                    id: contact.id,
                    displayName: contact.displayName,
                    verified: contact.isVerified
                )
            }
        } catch {
            return []
        }
    }

    func removeContact(id: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        _ = try repository.removeContact(id: id)
        contacts.removeAll { $0.id == id }
    }

    func verifyContact(id: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.verifyContact(id: id)
        await loadContacts()
    }

    // MARK: - Demo Contact
    // Based on: features/demo_contact.feature

    /// Initialize demo contact if user has no real contacts.
    /// Call this after onboarding completes.
    func initDemoContactIfNeeded() async {
        guard let repository = repository else { return }

        do {
            demoContact = try repository.initDemoContactIfNeeded()
            demoContactState = repository.getDemoContactState()
        } catch {
            print("VauchiViewModel: Failed to init demo contact: \(error)")
        }
    }

    /// Load the current demo contact state
    func loadDemoContact() async {
        guard let repository = repository else { return }

        do {
            demoContact = try repository.getDemoContact()
            demoContactState = repository.getDemoContactState()
        } catch {
            demoContact = nil
            demoContactState = repository.getDemoContactState()
        }
    }

    /// Dismiss the demo contact manually
    func dismissDemoContact() async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.dismissDemoContact()
        demoContact = nil
        demoContactState = repository.getDemoContactState()
    }

    /// Auto-remove demo contact after first real exchange
    func autoRemoveDemoContact() async {
        guard let repository = repository else { return }

        do {
            let removed = try repository.autoRemoveDemoContact()
            if removed {
                demoContact = nil
                demoContactState = repository.getDemoContactState()
            }
        } catch {
            print("VauchiViewModel: Failed to auto-remove demo contact: \(error)")
        }
    }

    /// Restore the demo contact from Settings
    func restoreDemoContact() async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        demoContact = try repository.restoreDemoContact()
        demoContactState = repository.getDemoContactState()
    }

    /// Trigger a demo update
    func triggerDemoUpdate() async {
        guard let repository = repository else { return }

        do {
            demoContact = try repository.triggerDemoUpdate()
            demoContactState = repository.getDemoContactState()
        } catch {
            print("VauchiViewModel: Failed to trigger demo update: \(error)")
        }
    }

    /// Check if demo update is available
    func isDemoUpdateAvailable() -> Bool {
        guard let repository = repository else { return false }
        return repository.isDemoUpdateAvailable()
    }

    // MARK: - Visibility Labels
    // Based on: features/visibility_labels.feature

    /// Load all visibility labels
    func loadLabels() async {
        guard let repository = repository else { return }

        do {
            visibilityLabels = try repository.listLabels()
            suggestedLabels = repository.getSuggestedLabels()
        } catch {
            print("VauchiViewModel: Failed to load labels: \(error)")
            visibilityLabels = []
        }
    }

    /// Create a new visibility label
    func createLabel(name: String) async throws -> VauchiVisibilityLabel {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let label = try repository.createLabel(name: name)
        await loadLabels()
        return label
    }

    /// Get label details
    func getLabel(id: String) throws -> VauchiVisibilityLabelDetail {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getLabel(id: id)
    }

    /// Rename a visibility label
    func renameLabel(id: String, newName: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.renameLabel(id: id, newName: newName)
        await loadLabels()
    }

    /// Delete a visibility label
    func deleteLabel(id: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.deleteLabel(id: id)
        await loadLabels()
    }

    /// Add contact to a label
    func addContactToLabel(labelId: String, contactId: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.addContactToLabel(labelId: labelId, contactId: contactId)
        await loadLabels()
    }

    /// Remove contact from a label
    func removeContactFromLabel(labelId: String, contactId: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.removeContactFromLabel(labelId: labelId, contactId: contactId)
        await loadLabels()
    }

    /// Get all labels for a contact
    func getLabelsForContact(contactId: String) throws -> [VauchiVisibilityLabel] {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getLabelsForContact(contactId: contactId)
    }

    /// Set field visibility for a label
    func setLabelFieldVisibility(labelId: String, fieldLabel: String, isVisible: Bool) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.setLabelFieldVisibility(labelId: labelId, fieldLabel: fieldLabel, isVisible: isVisible)
        await loadLabels()
    }

    // MARK: - Exchange

    func generateQRData() throws -> String {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let exchangeData = try repository.generateExchangeQr()
        return exchangeData.qrData
    }

    func generateExchangeData() throws -> ExchangeDataInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let data = try repository.generateExchangeQr()
        return ExchangeDataInfo(
            qrData: data.qrData,
            publicId: data.publicId,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(data.expiresAt))
        )
    }

    func completeExchange(qrData: String) async throws -> ExchangeResultInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let result = try repository.completeExchange(qrData: qrData)
        await loadContacts()

        // Auto-remove demo contact after first real exchange
        if result.success {
            await autoRemoveDemoContact()
        }

        return ExchangeResultInfo(
            contactId: result.contactId,
            contactName: result.contactName,
            success: result.success,
            errorMessage: result.errorMessage
        )
    }

    // MARK: - Sync

    func sync() async {
        guard let repository = repository else {
            syncState = .error("Not initialized")
            return
        }

        syncState = .syncing

        do {
            let result = try repository.sync()
            syncState = .success(
                contactsAdded: Int(result.contactsAdded),
                cardsUpdated: Int(result.cardsUpdated),
                updatesSent: Int(result.updatesSent)
            )
            lastSyncTime = Date()
            SettingsService.shared.lastSyncTime = lastSyncTime
            await loadContacts()
            await loadPendingUpdates()
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    func loadPendingUpdates() async {
        guard let repository = repository else { return }

        do {
            pendingUpdates = Int(try repository.pendingUpdateCount())
        } catch {
            pendingUpdates = 0
        }
    }

    // MARK: - Delivery Status

    func loadDeliveryRecords() async {
        guard let repository = repository else { return }

        do {
            deliveryRecords = try repository.getAllDeliveryRecords()
            failedDeliveryCount = deliveryRecords.filter { $0.isFailed }.count
        } catch {
            deliveryRecords = []
            failedDeliveryCount = 0
        }
    }

    func loadRetryEntries() async {
        guard let repository = repository else { return }

        do {
            retryEntries = try repository.getRetryEntries()
        } catch {
            retryEntries = []
        }
    }

    func getDeliveryRecordsForContact(contactId: String) async -> [VauchiDeliveryRecord] {
        guard let repository = repository else { return [] }

        do {
            return try repository.getDeliveryRecordsForContact(contactId: contactId)
        } catch {
            return []
        }
    }

    func getDeliverySummary(messageId: String) async -> VauchiDeliverySummary? {
        guard let repository = repository else { return nil }

        do {
            return try repository.getDeliverySummary(messageId: messageId)
        } catch {
            return nil
        }
    }

    func retryDelivery(messageId: String) async -> Bool {
        guard let repository = repository else { return false }

        do {
            let success = try repository.retryDelivery(messageId: messageId)
            if success {
                await loadDeliveryRecords()
                await loadRetryEntries()
            }
            return success
        } catch {
            return false
        }
    }

    /// Get the latest delivery status for a contact
    func getLatestDeliveryStatusForContact(contactId: String) -> VauchiDeliveryStatus? {
        // Check cached delivery records first
        if let latestRecord = deliveryRecords.first(where: { $0.recipientId == contactId }) {
            return latestRecord.status
        }
        return nil
    }

    /// Check if a contact has any pending deliveries
    func hasPendingDeliveryForContact(contactId: String) -> Bool {
        return deliveryRecords.contains { record in
            record.recipientId == contactId &&
            (record.status == .queued || record.status == .sent || record.status == .stored)
        }
    }

    // MARK: - Backup

    func exportBackup(password: String) async throws -> String {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.exportBackup(password: password)
    }

    func importBackup(data: String, password: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.importBackup(data: data, password: password)
        hasIdentity = true
        await loadIdentity()
        await loadCard()
        await loadContacts()
    }

    // MARK: - Visibility

    func hideFieldFromContact(contactId: String, fieldLabel: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.hideFieldFromContact(contactId: contactId, fieldLabel: fieldLabel)
    }

    func showFieldToContact(contactId: String, fieldLabel: String) async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.showFieldToContact(contactId: contactId, fieldLabel: fieldLabel)
    }

    func isFieldVisibleToContact(contactId: String, fieldLabel: String) async throws -> Bool {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.isFieldVisibleToContact(contactId: contactId, fieldLabel: fieldLabel)
    }

    // MARK: - Social Networks

    func listSocialNetworks() -> [(id: String, displayName: String, urlTemplate: String)] {
        guard let repository = repository else { return [] }

        return repository.listSocialNetworks().map {
            (id: $0.id, displayName: $0.displayName, urlTemplate: $0.urlTemplate)
        }
    }

    func getProfileUrl(networkId: String, username: String) -> String? {
        guard let repository = repository else { return nil }

        return repository.getProfileUrl(networkId: networkId, username: username)
    }

    // MARK: - Content Updates

    /// Check if content updates feature is supported
    func isContentUpdatesSupported() -> Bool {
        guard let repository = repository else { return false }
        return repository.isContentUpdatesSupported()
    }

    /// Check for available content updates
    func checkContentUpdates() async throws -> MobileUpdateStatus {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.checkContentUpdates()
    }

    /// Apply available content updates
    func applyContentUpdates() async throws -> MobileApplyResult {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.applyContentUpdates()
    }

    /// Reload social networks after content updates
    func reloadSocialNetworks() async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        try repository.reloadSocialNetworks()
    }

    // MARK: - Aha Moments (Progressive Onboarding)

    /// Try to trigger an aha moment and display it
    func tryTriggerAhaMoment(_ momentType: MobileAhaMomentType) {
        guard let repository = repository else { return }
        do {
            if let moment = try repository.tryTriggerAhaMoment(momentType) {
                DispatchQueue.main.async {
                    self.currentAhaMoment = moment
                }
            }
        } catch {
            // Silently fail - aha moments are non-critical
        }
    }

    /// Try to trigger an aha moment with context
    func tryTriggerAhaMomentWithContext(_ momentType: MobileAhaMomentType, context: String) {
        guard let repository = repository else { return }
        do {
            if let moment = try repository.tryTriggerAhaMomentWithContext(momentType, context: context) {
                DispatchQueue.main.async {
                    self.currentAhaMoment = moment
                }
            }
        } catch {
            // Silently fail - aha moments are non-critical
        }
    }

    /// Dismiss the current aha moment
    func dismissAhaMoment() {
        currentAhaMoment = nil
    }

    /// Check if user has seen a specific aha moment
    func hasSeenAhaMoment(_ momentType: MobileAhaMomentType) -> Bool {
        guard let repository = repository else { return true }
        return repository.hasSeenAhaMoment(momentType)
    }

    /// Get aha moments progress (seen/total)
    func ahaMomentsProgress() -> (seen: Int, total: Int) {
        guard let repository = repository else { return (0, 0) }
        return (Int(repository.ahaMomentsSeenCount()), Int(repository.ahaMomentsTotalCount()))
    }

    /// Reset aha moments (for Settings)
    func resetAhaMoments() async throws {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        try repository.resetAhaMoments()
    }

    // MARK: - Certificate Pinning

    /// Check if certificate pinning is enabled
    func isCertificatePinningEnabled() -> Bool {
        guard let repository = repository else { return false }
        return repository.isCertificatePinningEnabled()
    }

    /// Set the pinned certificate for relay TLS connections
    func setPinnedCertificate(_ certPem: String) {
        guard let repository = repository else { return }
        repository.setPinnedCertificate(certPem)
    }

    // MARK: - Recovery

    /// Create a recovery claim for a lost identity
    func createRecoveryClaim(oldPkHex: String) async throws -> VauchiRepository.RecoveryClaimInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.createRecoveryClaim(oldPkHex: oldPkHex)
    }

    /// Parse a recovery claim from base64
    func parseRecoveryClaim(claimB64: String) async throws -> VauchiRepository.RecoveryClaimInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.parseRecoveryClaim(claimB64: claimB64)
    }

    /// Create a voucher for someone's recovery claim
    func createRecoveryVoucher(claimB64: String) async throws -> VauchiRepository.RecoveryVoucherInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.createRecoveryVoucher(claimB64: claimB64)
    }

    /// Add a voucher to current recovery
    func addRecoveryVoucher(voucherB64: String) async throws -> VauchiRepository.RecoveryProgressInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.addRecoveryVoucher(voucherB64: voucherB64)
    }

    /// Get current recovery status
    func getRecoveryStatus() async throws -> VauchiRepository.RecoveryProgressInfo? {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getRecoveryStatus()
    }

    /// Get completed recovery proof
    func getRecoveryProof() async throws -> String? {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getRecoveryProof()
    }

    // MARK: - Device Management

    /// Get list of linked devices
    func getDevices() async throws -> [VauchiRepository.DeviceInfo] {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.getDevices()
    }

    /// Generate QR code data for linking a new device
    func generateDeviceLinkQr() async throws -> VauchiRepository.DeviceLinkData {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.generateDeviceLinkQr()
    }

    /// Parse device link QR code data
    func parseDeviceLinkQr(qrData: String) async throws -> VauchiRepository.DeviceLinkInfo {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.parseDeviceLinkQr(qrData: qrData)
    }

    /// Get the number of linked devices
    func deviceCount() async throws -> UInt32 {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.deviceCount()
    }

    /// Unlink a device by index
    func unlinkDevice(deviceIndex: UInt32) async throws -> Bool {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.unlinkDevice(deviceIndex: deviceIndex)
    }

    /// Check if this is the primary device
    func isPrimaryDevice() async throws -> Bool {
        guard let repository = repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.isPrimaryDevice()
    }
}
