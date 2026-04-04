// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiViewModel.swift
// Main state management for Vauchi iOS app

import Combine
import Foundation
import LocalAuthentication
import Security
import SwiftUI
import VauchiPlatform

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
    let recoveryTrusted: Bool
    let isHidden: Bool
    let fingerprint: String
    let card: CardInfo?
    let addedAt: Date?
    let trustLevel: MobileContactTrustLevel

    init(
        id: String,
        displayName: String,
        verified: Bool,
        recoveryTrusted: Bool = false,
        isHidden: Bool = false,
        fingerprint: String = "",
        card: CardInfo? = nil,
        addedAt: Date? = nil,
        trustLevel: MobileContactTrustLevel = .standard
    ) {
        self.id = id
        self.displayName = displayName
        self.verified = verified
        self.recoveryTrusted = recoveryTrusted
        self.isHidden = isHidden
        self.fingerprint = fingerprint
        self.card = card
        self.addedAt = addedAt
        self.trustLevel = trustLevel
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
    let audioChallenge: Data?

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
    case success(contactsAdded: Int, cardsUpdated: Int, updatesSent: Int, updatedContactNames: [String])
    case error(String)
}

/// Sync result
struct SyncResultInfo: Equatable {
    let contactsAdded: Int
    let cardsUpdated: Int
    let updatesSent: Int
}

/// App-level state for device lock handling
enum AppState: Equatable {
    case loading
    case waitingForUnlock // Layer B: protected data unavailable (prewarming)
    case authenticationRequired // Layer C: auth window expired
    case appPasswordRequired // Biometric OK, duress enabled — show app PIN
    case ready // Normal operation
}

@MainActor
class VauchiViewModel: ObservableObject {
    // MARK: - Published State

    @Published var appState: AppState = .loading
    @Published var isLoading = true
    @Published var hasIdentity = false
    @Published var identity: IdentityInfo?
    @Published var card: CardInfo?
    @Published var contacts: [ContactInfo] = []
    private let contactsPageSize: UInt32 = 20
    @Published var hasMoreContacts = true
    private var contactsOffset: UInt32 = 0
    @Published var errorMessage: String?
    @Published var syncState: SyncState = .idle
    @Published var lastSyncTime: Date?
    @Published var pendingUpdates: Int = 0

    /// Network state
    @Published var isOnline = false

    // Delivery status
    @Published var deliveryRecords: [VauchiDeliveryRecord] = []
    @Published var retryEntries: [VauchiRetryEntry] = []
    @Published var failedDeliveryCount: Int = 0

    // Demo contact (for users with no contacts)
    @Published var demoContact: VauchiDemoContact?
    @Published var demoContactState: VauchiDemoContactState?

    // GDPR
    @Published var deletionState: VauchiDeletionState = .none
    @Published var deletionInfo: VauchiDeletionInfo?
    @Published var consentRecords: [VauchiConsentRecord] = []

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

    /// Aha moments (progressive onboarding)
    @Published var currentAhaMoment: MobileAhaMoment?

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
        // Layer B: check if protected data is available before accessing Keychain
        guard UIApplication.shared.isProtectedDataAvailable else {
            #if DEBUG
                print("VauchiViewModel: protected data unavailable, waiting for unlock")
            #endif
            appState = .waitingForUnlock
            subscribeToProtectedDataAvailable()
            return
        }

        do {
            #if DEBUG
                print("VauchiViewModel: initializing repository...")
            #endif
            repository = try VauchiRepository(
                relayUrl: SettingsService.shared.relayUrl
            )
            appState = .ready
            #if DEBUG
                print("VauchiViewModel: repository initialized successfully")
            #endif
        } catch VauchiRepositoryError.deviceLocked {
            // Layer C: Keychain accessible but auth required
            #if DEBUG
                print("VauchiViewModel: device locked, authentication required")
            #endif
            appState = .authenticationRequired
        } catch {
            let msg = "Failed to initialize: \(error.localizedDescription) (\(String(describing: error)))"
            #if DEBUG
                print("VauchiViewModel: \(msg)")
            #endif
            errorMessage = msg
        }
    }

    private var protectedDataObserver: NSObjectProtocol?

    private func subscribeToProtectedDataAvailable() {
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeProtectedDataObserver()
            self?.initializeRepository()
        }
    }

    private func removeProtectedDataObserver() {
        if let observer = protectedDataObserver {
            NotificationCenter.default.removeObserver(observer)
            protectedDataObserver = nil
        }
    }

    /// Trigger system authentication (Face ID / Touch ID / passcode) and retry initialization
    func authenticateAndRetry() {
        let context = LAContext()
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: NSLocalizedString(
                "Unlock Vauchi to access your contacts",
                comment: "Biometric/passcode prompt reason"
            )
        ) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.initializeRepository()
                    // Hold on loading state during duress check
                    // to prevent real contacts from flashing if
                    // initializeRepository() set .ready.
                    self?.appState = .loading
                    // isDuressEnabled() reads SQLite — dispatch
                    // off main thread (matches Android's
                    // withContext(Dispatchers.IO) pattern).
                    // Constant-time delay prevents timing
                    // side-channel (observer can't infer
                    // isDuressEnabled from transition speed).
                    DispatchQueue.global(qos: .userInitiated).async {
                        let start = Date()
                        let duress = (try? self?.repository?
                            .isDuressEnabled()) == true
                        let elapsed = Date().timeIntervalSince(start)
                        let pad = max(0, 0.3 - elapsed)
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + pad
                        ) {
                            if duress {
                                self?.appState = .appPasswordRequired
                            } else {
                                self?.appState = .ready
                                self?.loadState()
                            }
                        }
                    }
                } else {
                    // If cancelled/failed, stay on lock screen — user can tap again
                    #if DEBUG
                        print("VauchiViewModel: authentication failed or cancelled: \(String(describing: error))")
                    #endif
                }
            }
        }
    }

    /// Authenticate with app password (duress-enabled flow).
    /// Core decides Normal vs Duress based on which PIN matches.
    /// Runs Argon2 verification off main thread to avoid UI freeze.
    func authenticateAppPassword(_ pin: String) async throws {
        guard let repo = repository else {
            throw NSError(
                domain: "Vauchi", code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Repository not initialized",
                ]
            )
        }
        try await Task.detached(priority: .userInitiated) {
            _ = try repo.authenticate(password: pin)
        }.value
        loadState()
        appState = .ready
    }

    private func setupNetworkMonitoring() {
        // Subscribe to network connectivity changes
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected

                // Auto-sync when connection restored (if enabled and has identity)
                if isConnected, SettingsService.shared.autoSyncEnabled, self?.hasIdentity ?? false {
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
        // Don't attempt to load if we're waiting for unlock or auth
        if appState == .waitingForUnlock || appState == .authenticationRequired {
            isLoading = false
            return
        }

        // Don't clear error if repository failed to initialize
        if repository == nil, errorMessage != nil {
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
        guard let repository else {
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
        guard let repository else { return }

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
        guard let repository else { return }

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
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let fieldType = VauchiFieldType(rawValue: type) ?? .custom
        try repository.addField(type: fieldType, label: label, value: value)
        await loadCard()
    }

    func updateField(label: String, newValue: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.updateField(label: label, newValue: newValue)
        await loadCard()
    }

    func removeField(id: String) async throws {
        guard let repository else {
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
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.setDisplayName(name)
        await loadIdentity()
        await loadCard()
    }

    // MARK: - Contacts

    func loadContacts() async {
        guard let repository else { return }

        // Reset pagination
        contactsOffset = 0
        hasMoreContacts = true

        do {
            let contactsData = try repository.listContactsPaginated(offset: 0, limit: contactsPageSize)
            contacts = contactsData.map { contact in
                ContactInfo(
                    id: contact.id,
                    displayName: contact.displayName,
                    verified: contact.isVerified,
                    recoveryTrusted: contact.isRecoveryTrusted,
                    isHidden: contact.isHidden,
                    fingerprint: contact.fingerprint,
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
                    addedAt: Date(timeIntervalSince1970: TimeInterval(contact.addedAt)),
                    trustLevel: contact.trustLevel
                )
            }
            contactsOffset = UInt32(contacts.count)
            hasMoreContacts = contactsData.count == Int(contactsPageSize)
        } catch {
            contacts = []
            hasMoreContacts = false
        }
    }

    func loadMoreContacts() async {
        guard let repository, hasMoreContacts else { return }

        do {
            let moreData = try repository.listContactsPaginated(offset: contactsOffset, limit: contactsPageSize)
            let moreContacts = moreData.map { contact in
                ContactInfo(
                    id: contact.id,
                    displayName: contact.displayName,
                    verified: contact.isVerified,
                    recoveryTrusted: contact.isRecoveryTrusted,
                    isHidden: contact.isHidden,
                    fingerprint: contact.fingerprint,
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
                    addedAt: Date(timeIntervalSince1970: TimeInterval(contact.addedAt)),
                    trustLevel: contact.trustLevel
                )
            }
            contacts.append(contentsOf: moreContacts)
            contactsOffset += UInt32(moreContacts.count)
            hasMoreContacts = moreData.count == Int(contactsPageSize)
        } catch {
            hasMoreContacts = false
        }
    }

    func getContact(id: String) async -> ContactInfo? {
        guard let repository else { return nil }

        do {
            guard let contact = try repository.getContact(id: id) else {
                return nil
            }

            return ContactInfo(
                id: contact.id,
                displayName: contact.displayName,
                verified: contact.isVerified,
                isHidden: contact.isHidden,
                fingerprint: contact.fingerprint,
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
                addedAt: Date(timeIntervalSince1970: TimeInterval(contact.addedAt)),
                trustLevel: contact.trustLevel
            )
        } catch {
            return nil
        }
    }

    func searchContacts(query: String) async -> [ContactInfo] {
        guard let repository else { return [] }

        do {
            let results = try repository.searchContacts(query: query)
            return results.map { contact in
                ContactInfo(
                    id: contact.id,
                    displayName: contact.displayName,
                    verified: contact.isVerified,
                    recoveryTrusted: contact.isRecoveryTrusted,
                    fingerprint: contact.fingerprint,
                    trustLevel: contact.trustLevel
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Hidden Contacts

    // Based on: features/resistance.feature - R3 Hidden Contact UI

    /// Load hidden contacts
    func loadHiddenContacts() async {
        guard let repository else { return }

        do {
            let hiddenData = try repository.listHiddenContacts()
            contacts = hiddenData.map { contact in
                ContactInfo(
                    id: contact.id,
                    displayName: contact.displayName,
                    verified: contact.isVerified,
                    recoveryTrusted: contact.isRecoveryTrusted,
                    isHidden: contact.isHidden,
                    fingerprint: contact.fingerprint,
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
                    addedAt: Date(timeIntervalSince1970: TimeInterval(contact.addedAt)),
                    trustLevel: contact.trustLevel
                )
            }
        } catch {
            // Gracefully handle if method not available yet in UniFFI bindings
            #if DEBUG
                print("VauchiViewModel: loadHiddenContacts not yet available: \(error)")
            #endif
            contacts = []
        }
    }

    /// Hide a contact
    func hideContact(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        do {
            try repository.hideContact(id: id)
            // Remove from current contacts list
            contacts.removeAll { $0.id == id }
        } catch {
            // Gracefully handle if method not available yet
            #if DEBUG
                print("VauchiViewModel: hideContact not yet available: \(error)")
            #endif
            throw VauchiRepositoryError.internalError("Hidden contacts feature not yet available")
        }
    }

    /// Import contacts from vCard (.vcf) file data.
    func importContactsFromVcf(_ data: Data) async throws -> ImportResult {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let result = try repository.importContactsFromVcf(data)
        // Refresh contacts list after import
        await loadContacts()
        return ImportResult(
            imported: result.imported,
            skipped: result.skipped,
            warnings: result.warnings
        )
    }

    /// Unhide a contact
    func unhideContact(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        do {
            try repository.unhideContact(id: id)
            // Remove from hidden contacts list
            contacts.removeAll { $0.id == id }
        } catch {
            // Gracefully handle if method not available yet
            #if DEBUG
                print("VauchiViewModel: unhideContact not yet available: \(error)")
            #endif
            throw VauchiRepositoryError.internalError("Hidden contacts feature not yet available")
        }
    }

    // MARK: - Duress PIN

    // Based on: features/duress_pin.feature - R1 Duress PIN

    @Published var isPasswordEnabled = false
    @Published var isDuressEnabled = false

    /// Load duress status
    func loadDuressStatus() async {
        guard let repository else { return }

        do {
            isPasswordEnabled = try repository.isPasswordEnabled()
            isDuressEnabled = try repository.isDuressEnabled()
        } catch {
            #if DEBUG
                print("VauchiViewModel: loadDuressStatus not yet available: \(error)")
            #endif
        }
    }

    /// Set up app password
    func setupAppPassword(password: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.setupAppPassword(password: password)
        isPasswordEnabled = true
    }

    /// Set up duress PIN
    func setupDuressPassword(duressPassword: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.setupDuressPassword(duressPassword: duressPassword)
        isDuressEnabled = true
    }

    /// Disable duress PIN
    func disableDuress() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.disableDuress()
        isDuressEnabled = false
    }

    // MARK: - Panic Shred

    // Based on: features/panic_widget.feature - R2 Panic Widget

    /// Execute emergency panic shred — destroys all data immediately
    func panicShred() async {
        guard let repository else { return }

        do {
            try repository.panicShred()
        } catch {
            #if DEBUG
                print("VauchiViewModel: panicShred not yet available: \(error)")
            #endif
        }
    }

    // MARK: - Tor Mode

    @Published var isTorEnabled: Bool = false
    @Published var torPreferOnion: Bool = true
    @Published var torBridges: [String] = []

    // MARK: - Emergency Broadcast

    @Published var emergencyConfigured = false

    func loadEmergencyConfig() async {
        guard let repository else { return }
        do {
            let config = try repository.getEmergencyConfig()
            emergencyConfigured = config != nil
        } catch {
            #if DEBUG
                print("VauchiViewModel: loadEmergencyConfig not yet available: \(error)")
            #endif
        }
    }

    func configureEmergencyBroadcast(contactIds: [String], message: String, includeLocation: Bool) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.configureEmergencyBroadcast(
            contactIds: contactIds,
            message: message,
            includeLocation: includeLocation
        )
        emergencyConfigured = true
    }

    func sendEmergencyBroadcast() async throws -> (sent: Int, total: Int) {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        return try repository.sendEmergencyBroadcast()
    }

    func disableEmergencyBroadcast() async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.disableEmergencyBroadcast()
        emergencyConfigured = false
    }

    // MARK: - Tor Mode

    func loadTorConfig() {
        guard let repository else { return }
        do {
            let config = try repository.getTorConfig()
            DispatchQueue.main.async {
                self.isTorEnabled = config.enabled
                self.torPreferOnion = config.preferOnion
                self.torBridges = config.bridges
            }
        } catch {
            #if DEBUG
                print("Failed to load Tor config: \(error)")
            #endif
        }
    }

    func saveTorConfig(enabled: Bool, bridges: [String], preferOnion: Bool) {
        guard let repository else { return }
        do {
            try repository.saveTorConfig(enabled: enabled, bridges: bridges, preferOnion: preferOnion)
            DispatchQueue.main.async {
                self.isTorEnabled = enabled
                self.torPreferOnion = preferOnion
                self.torBridges = bridges
            }
        } catch {
            #if DEBUG
                print("Failed to save Tor config: \(error)")
            #endif
        }
    }

    func removeContact(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        _ = try repository.removeContact(id: id)
        contacts.removeAll { $0.id == id }
    }

    func verifyContact(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.verifyContact(id: id)
        await loadContacts()
    }

    /// Get own identity fingerprint for verification display.
    func getOwnFingerprint() -> String? {
        guard let repository else { return nil }
        return try? repository.getOwnFingerprint()
    }

    func trustContactForRecovery(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.trustContactForRecovery(id: id)
        await loadContacts()
    }

    func untrustContactForRecovery(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.untrustContactForRecovery(id: id)
        await loadContacts()
    }

    func trustedContactCount() async throws -> UInt32 {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.trustedContactCount()
    }

    // MARK: - Demo Contact

    // Based on: features/demo_contact.feature

    /// Initialize demo contact if user has no real contacts.
    /// Call this after onboarding completes.
    func initDemoContactIfNeeded() async {
        guard let repository else { return }

        do {
            demoContact = try repository.initDemoContactIfNeeded()
            demoContactState = repository.getDemoContactState()
        } catch {
            #if DEBUG
                print("VauchiViewModel: Failed to init demo contact: \(error)")
            #endif
        }
    }

    /// Load the current demo contact state
    func loadDemoContact() async {
        guard let repository else { return }

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
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.dismissDemoContact()
        demoContact = nil
        demoContactState = repository.getDemoContactState()
    }

    /// Auto-remove demo contact after first real exchange
    func autoRemoveDemoContact() async {
        guard let repository else { return }

        do {
            let removed = try repository.autoRemoveDemoContact()
            if removed {
                demoContact = nil
                demoContactState = repository.getDemoContactState()
            }
        } catch {
            #if DEBUG
                print("VauchiViewModel: Failed to auto-remove demo contact: \(error)")
            #endif
        }
    }

    /// Restore the demo contact from Settings
    func restoreDemoContact() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        demoContact = try repository.restoreDemoContact()
        demoContactState = repository.getDemoContactState()
    }

    /// Trigger a demo update
    func triggerDemoUpdate() async {
        guard let repository else { return }

        do {
            demoContact = try repository.triggerDemoUpdate()
            demoContactState = repository.getDemoContactState()
        } catch {
            #if DEBUG
                print("VauchiViewModel: Failed to trigger demo update: \(error)")
            #endif
        }
    }

    /// Check if demo update is available
    func isDemoUpdateAvailable() -> Bool {
        guard let repository else { return false }
        return repository.isDemoUpdateAvailable()
    }

    // MARK: - Visibility Labels

    // Based on: features/visibility_labels.feature

    /// Load all visibility labels
    func loadLabels() async {
        guard let repository else { return }

        do {
            visibilityLabels = try repository.listLabels()
            suggestedLabels = repository.getSuggestedLabels()
        } catch {
            #if DEBUG
                print("VauchiViewModel: Failed to load labels: \(error)")
            #endif
            visibilityLabels = []
        }
    }

    /// Create a new visibility label
    func createLabel(name: String) async throws -> VauchiVisibilityLabel {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let label = try repository.createLabel(name: name)
        await loadLabels()
        return label
    }

    /// Get label details
    func getLabel(id: String) throws -> VauchiVisibilityLabelDetail {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getLabel(id: id)
    }

    /// Rename a visibility label
    func renameLabel(id: String, newName: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.renameLabel(id: id, newName: newName)
        await loadLabels()
    }

    /// Delete a visibility label
    func deleteLabel(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.deleteLabel(id: id)
        await loadLabels()
    }

    /// Add contact to a label
    func addContactToLabel(labelId: String, contactId: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.addContactToLabel(labelId: labelId, contactId: contactId)
        await loadLabels()
    }

    /// Remove contact from a label
    func removeContactFromLabel(labelId: String, contactId: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.removeContactFromLabel(labelId: labelId, contactId: contactId)
        await loadLabels()
    }

    /// Get all labels for a contact
    func getLabelsForContact(contactId: String) throws -> [VauchiVisibilityLabel] {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getLabelsForContact(contactId: contactId)
    }

    /// Set field visibility for a label
    func setLabelFieldVisibility(labelId: String, fieldLabel: String, isVisible: Bool) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.setLabelFieldVisibility(labelId: labelId, fieldLabel: fieldLabel, isVisible: isVisible)
        await loadLabels()
    }

    // MARK: - Multi-Stage Exchange

    /// Multi-stage exchange session — drives the cycling QR protocol
    private(set) var multiStageSession: MobileMultiStageSession?

    func startMultiStageExchange() {
        guard let repository else { return }
        do {
            multiStageSession = try repository.createMultistageSession()
        } catch {
            #if DEBUG
                NSLog("[Exchange] Failed to create session: %@", "\(error)")
            #endif
        }
    }

    func finalizeMultiStageExchange() -> MobileExchangeResult? {
        guard let repository, let session = multiStageSession else { return nil }
        do {
            return try repository.finalizeMultistageExchange(session: session)
        } catch {
            #if DEBUG
                NSLog("[Exchange] Failed to finalize: %@", "\(error)")
            #endif
            return nil
        }
    }

    func getMultiStageDisplayQr() -> MobileQrPayload? {
        multiStageSession?.getDisplayQr()
    }

    func processMultiStageQr(raw: String) -> MobileProtocolState {
        guard let session = multiStageSession else { return .failed(reason: "No session") }
        return session.processScannedQr(raw: raw)
    }

    func getMultiStageState() -> MobileProtocolState {
        multiStageSession?.getState() ?? .idle
    }

    func getMultiStageReceivedData() -> Data? {
        multiStageSession?.getReceivedData()
    }

    func cancelMultiStageExchange() {
        multiStageSession?.cancel()
        multiStageSession = nil
    }

    // Proximity stubs — ultrasonic removed from exchange. Kept for device linking views.
    @Published var proximitySupported = false
    var proximityCapability: String {
        "none"
    }

    func emitProximityChallenge(_: Data) -> Bool {
        false
    }

    func listenForProximityResponse(timeoutMs _: UInt64 = 5000) -> Data? {
        nil
    }

    func stopProximityVerification() {}

    /// Start an exchange from a deep link payload.
    /// Called after the user grants consent in the deep link consent gate (SP-9).
    /// TODO: Deep links use the old wb:// single-QR format. Re-implement when
    /// the multi-stage protocol supports deep link payloads.
    func startExchangeWithDeepLink(payload _: String) {
        showError("Not Supported",
                  message: "Deep link exchange is not yet supported with the new protocol.")
    }

    // MARK: - Sync

    func sync() async {
        guard let repository else {
            syncState = .error("Not initialized")
            return
        }

        syncState = .syncing

        do {
            let result = try repository.sync()
            let names = result.updatedContactNames
            syncState = .success(
                contactsAdded: Int(result.contactsAdded),
                cardsUpdated: Int(result.cardsUpdated),
                updatesSent: Int(result.updatesSent),
                updatedContactNames: names
            )
            lastSyncTime = Date()
            SettingsService.shared.lastSyncTime = lastSyncTime
            await loadContacts()
            await loadPendingUpdates()
            if !names.isEmpty {
                let loc = LocalizationService.shared
                let msg = names.count == 1
                    ? loc.t("sync.updated_single", args: ["name": names.first!])
                    : loc.t("sync.updated_contacts", args: ["names": names.joined(separator: ", ")])
                showSuccess("Sync", message: msg)
            }
        } catch let VauchiRepositoryError.rateLimited(retryAfterSecs) {
            syncState = .error("Rate limited")
            showError("Sync", message: "Please wait \(retryAfterSecs)s before syncing again")
        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    func loadPendingUpdates() async {
        guard let repository else { return }

        do {
            pendingUpdates = try Int(repository.pendingUpdateCount())
        } catch {
            pendingUpdates = 0
        }
    }

    // MARK: - Delivery Status

    func loadDeliveryRecords() async {
        guard let repository else { return }

        do {
            deliveryRecords = try repository.getAllDeliveryRecords()
            failedDeliveryCount = deliveryRecords.filter(\.isFailed).count
        } catch {
            deliveryRecords = []
            failedDeliveryCount = 0
        }
    }

    func loadRetryEntries() async {
        guard let repository else { return }

        do {
            retryEntries = try repository.getRetryEntries()
        } catch {
            retryEntries = []
        }
    }

    func getDeliveryRecordsForContact(contactId: String) async -> [VauchiDeliveryRecord] {
        guard let repository else { return [] }

        do {
            return try repository.getDeliveryRecordsForContact(contactId: contactId)
        } catch {
            return []
        }
    }

    func getDeliverySummary(messageId: String) async -> VauchiDeliverySummary? {
        guard let repository else { return nil }

        do {
            return try repository.getDeliverySummary(messageId: messageId)
        } catch {
            return nil
        }
    }

    func retryDelivery(messageId: String) async -> Bool {
        guard let repository else { return false }

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

    /// Get the latest delivery status for a contact (delegates to core via repository)
    func getLatestDeliveryStatusForContact(contactId: String) -> VauchiDeliveryStatus? {
        guard let repository else { return nil }
        let records = (try? repository.getDeliveryRecordsForContact(contactId: contactId)) ?? []
        return records.first?.status
    }

    /// Check if a contact has any pending deliveries (delegates to core via repository)
    func hasPendingDeliveryForContact(contactId: String) -> Bool {
        guard let repository else { return false }
        let records = (try? repository.getDeliveryRecordsForContact(contactId: contactId)) ?? []
        return records.contains { record in
            record.status == .queued || record.status == .sent || record.status == .stored
        }
    }

    // MARK: - Backup

    func exportBackup(password: String) async throws -> String {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.exportBackup(password: password)
    }

    func importBackup(data: String, password: String) async throws {
        guard let repository else {
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
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.hideFieldFromContact(contactId: contactId, fieldLabel: fieldLabel)
    }

    func showFieldToContact(contactId: String, fieldLabel: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.showFieldToContact(contactId: contactId, fieldLabel: fieldLabel)
    }

    func isFieldVisibleToContact(contactId: String, fieldLabel: String) async throws -> Bool {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.isFieldVisibleToContact(contactId: contactId, fieldLabel: fieldLabel)
    }

    // MARK: - Social Networks

    func listSocialNetworks() -> [VauchiSocialNetwork] {
        guard let repository else { return [] }

        return repository.listSocialNetworks()
    }

    func getProfileUrl(networkId: String, username: String) -> String? {
        guard let repository else { return nil }

        return repository.getProfileUrl(networkId: networkId, username: username)
    }

    // MARK: - Content Updates

    /// Check if content updates feature is supported
    func isContentUpdatesSupported() -> Bool {
        guard let repository else { return false }
        return repository.isContentUpdatesSupported()
    }

    /// Check for available content updates
    func checkContentUpdates() async throws -> MobileUpdateStatus {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.checkContentUpdates()
    }

    /// Apply available content updates
    func applyContentUpdates() async throws -> MobileApplyResult {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.applyContentUpdates()
    }

    /// Reload social networks after content updates
    func reloadSocialNetworks() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        try repository.reloadSocialNetworks()
    }

    // MARK: - Aha Moments (Progressive Onboarding)

    /// Try to trigger an aha moment and display it
    func tryTriggerAhaMoment(_ momentType: MobileAhaMomentType) {
        guard let repository else { return }
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
        guard let repository else { return }
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
        guard let repository else { return true }
        return repository.hasSeenAhaMoment(momentType)
    }

    /// Get aha moments progress (seen/total)
    func ahaMomentsProgress() -> (seen: Int, total: Int) {
        guard let repository else { return (0, 0) }
        return (Int(repository.ahaMomentsSeenCount()), Int(repository.ahaMomentsTotalCount()))
    }

    /// Reset aha moments (for Settings)
    func resetAhaMoments() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        try repository.resetAhaMoments()
    }

    // MARK: - Certificate Pinning

    /// Check if certificate pinning is enabled
    func isCertificatePinningEnabled() -> Bool {
        guard let repository else { return false }
        return repository.isCertificatePinningEnabled()
    }

    /// Set the pinned certificate for relay TLS connections
    func setPinnedCertificate(_ certPem: String) {
        guard let repository else { return }
        repository.setPinnedCertificate(certPem)
    }

    // MARK: - Recovery

    /// Create a recovery claim for a lost identity
    func createRecoveryClaim(oldPkHex: String) async throws -> VauchiRepository.RecoveryClaimInfo {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.createRecoveryClaim(oldPkHex: oldPkHex)
    }

    /// Parse a recovery claim from base64
    func parseRecoveryClaim(claimB64: String) async throws -> VauchiRepository.RecoveryClaimInfo {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.parseRecoveryClaim(claimB64: claimB64)
    }

    /// Create a voucher for someone's recovery claim
    func createRecoveryVoucher(claimB64: String) async throws -> VauchiRepository.RecoveryVoucherInfo {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.createRecoveryVoucher(claimB64: claimB64)
    }

    /// Add a voucher to current recovery
    func addRecoveryVoucher(voucherB64: String) async throws -> VauchiRepository.RecoveryProgressInfo {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.addRecoveryVoucher(voucherB64: voucherB64)
    }

    /// Get current recovery status
    func getRecoveryStatus() async throws -> VauchiRepository.RecoveryProgressInfo? {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getRecoveryStatus()
    }

    /// Get completed recovery proof
    func getRecoveryProof() async throws -> String? {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getRecoveryProof()
    }

    // MARK: - Device Management

    /// Get list of linked devices
    func getDevices() async throws -> [VauchiRepository.DeviceInfo] {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.getDevices()
    }

    /// Generate QR code data for linking a new device
    /// Create NFC initiator handshake session for iOS reader.
    func createNfcInitiator() throws -> MobileNfcHandshake {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.createNfcInitiator()
    }

    func generateDeviceLinkQr() async throws -> VauchiRepository.DeviceLinkData {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.generateDeviceLinkQr()
    }

    /// Parse device link QR code data
    func parseDeviceLinkQr(qrData: String) async throws -> VauchiRepository.DeviceLinkInfo {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.parseDeviceLinkQr(qrData: qrData)
    }

    /// Get the number of linked devices
    func deviceCount() async throws -> UInt32 {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.deviceCount()
    }

    /// Unlink a device by index
    func unlinkDevice(deviceIndex: UInt32) async throws -> Bool {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.unlinkDevice(deviceIndex: deviceIndex)
    }

    /// Check if this is the primary device
    func isPrimaryDevice() async throws -> Bool {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }
        return try repository.isPrimaryDevice()
    }

    // MARK: - Device Linking Protocol

    enum DeviceLinkState {
        case idle
        case generatingQR
        case waitingForRequest
        case confirmingDevice(name: String, code: String, challenge: Data)
        case verifyingProximity(challenge: Data, confirmationCode: String)
        case completing
        case success
        case failed(String)
    }

    @Published var deviceLinkState: DeviceLinkState = .idle
    private var currentInitiator: MobileDeviceLinkInitiator?
    private var currentSenderToken: String?

    /// Start the initiator flow: generate QR, listen for request.
    func startDeviceLinkInitiator() async throws -> String {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        deviceLinkState = .generatingQR
        let initiator = try repository.startDeviceLink()
        currentInitiator = initiator
        let qrData = initiator.qrData()
        deviceLinkState = .waitingForRequest
        return qrData
    }

    /// Listen for device link request via relay (blocking, call from background).
    func listenForDeviceLinkRequest() async throws {
        guard let repository, let initiator = currentInitiator else {
            throw VauchiRepositoryError.notInitialized
        }

        let request = try repository.listenForDeviceLinkRequest(timeoutSecs: 300)
        currentSenderToken = request.senderToken
        let confirmation = try initiator.prepareConfirmation(
            encryptedRequest: request.encryptedPayload
        )

        let challenge = Data(initiator.proximityChallenge())

        deviceLinkState = .confirmingDevice(
            name: confirmation.deviceName,
            code: confirmation.confirmationCode,
            challenge: challenge
        )
    }

    /// Approve the device link with ultrasonic proximity proof.
    func approveDeviceLinkUltrasonic(challengeResponse: Data, verifiedAt: UInt64) async throws {
        guard let repository,
              let initiator = currentInitiator,
              let senderToken = currentSenderToken
        else {
            throw VauchiRepositoryError.notInitialized
        }

        deviceLinkState = .completing
        let result = try initiator.confirmLinkUltrasonic(
            challengeResponse: challengeResponse,
            verifiedAt: verifiedAt
        )
        if let responseBytes = result.encryptedResponse {
            try repository.sendDeviceLinkResponse(
                senderToken: senderToken,
                encryptedResponse: responseBytes
            )
        }
        deviceLinkState = .success
        currentInitiator = nil
        currentSenderToken = nil
    }

    /// Approve the device link with manual confirmation.
    func approveDeviceLinkManual(confirmationCode: String, confirmedAt: UInt64) async throws {
        guard let repository,
              let initiator = currentInitiator,
              let senderToken = currentSenderToken
        else {
            throw VauchiRepositoryError.notInitialized
        }

        deviceLinkState = .completing
        let result = try initiator.confirmLinkManual(
            confirmationCode: confirmationCode,
            confirmedAt: confirmedAt
        )
        if let responseBytes = result.encryptedResponse {
            try repository.sendDeviceLinkResponse(
                senderToken: senderToken,
                encryptedResponse: responseBytes
            )
        }
        deviceLinkState = .success
        currentInitiator = nil
        currentSenderToken = nil
    }

    /// Cancel the device link flow.
    func cancelDeviceLink() {
        deviceLinkState = .idle
        currentInitiator = nil
        currentSenderToken = nil
    }

    // MARK: - GDPR Operations

    /// Export all user data in GDPR-compliant format
    func exportGdprData() async throws -> VauchiGdprExport {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.exportGdprData()
    }

    /// Schedule identity deletion with grace period
    func scheduleIdentityDeletion() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let info = try repository.scheduleIdentityDeletion()
        deletionState = info.state
        deletionInfo = info
    }

    /// Cancel a scheduled identity deletion
    func cancelIdentityDeletion() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.cancelIdentityDeletion()
        deletionState = .none
        deletionInfo = nil
    }

    /// Load the current deletion state
    func loadDeletionState() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        let info = try repository.getDeletionState()
        deletionState = info.state
        deletionInfo = info
    }

    /// Grant consent for a specific type
    func grantConsent(_ type: VauchiConsentType) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.grantConsent(consentType: type)
        try await loadConsentRecords()
    }

    /// Revoke consent for a specific type
    func revokeConsent(_ type: VauchiConsentType) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.revokeConsent(consentType: type)
        try await loadConsentRecords()
    }

    /// Get aggregated consent status for a specific type
    func getConsentStatus(_ type: VauchiConsentType) throws -> MobileConsentStatus {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getConsentStatus(consentType: type)
    }

    /// Load all consent records
    func loadConsentRecords() async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        consentRecords = try repository.getConsentRecords()
    }
}
