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

    // MARK: - Private Properties

    private var repository: VauchiRepository?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        lastSyncTime = SettingsService.shared.lastSyncTime
        initializeRepository()
        setupNetworkMonitoring()
    }

    private func initializeRepository() {
        do {
            repository = try VauchiRepository(
                relayUrl: SettingsService.shared.relayUrl
            )
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
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
        isLoading = true
        errorMessage = nil

        Task {
            hasIdentity = repository?.hasIdentity() ?? false

            if hasIdentity {
                await loadIdentity()
                await loadCard()
                await loadContacts()
                await loadPendingUpdates()
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
}
