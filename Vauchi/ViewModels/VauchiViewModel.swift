// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiViewModel.swift
// Main state management for Vauchi iOS app

import Combine
import CoreUIModels
import Foundation
import LocalAuthentication
import Security
import SwiftUI
import VauchiPlatform

// `FieldInfo`, `CardInfo`, and `ContactInfo` struct wrappers were removed
// in Phase 1A.5 (core-gui-architecture-alignment) — consumers now use
// the repository-layer types (`VauchiContact`, `VauchiContactCard`,
// `VauchiContactField`) directly, eliminating the parallel-type round-trip
// that was flagged as an ADR-021 violation.

/// Sync state enum
enum SyncState: Equatable {
    case idle
    case syncing
    case success(contactsAdded: Int, cardsUpdated: Int, updatesSent: Int, updatedContactNames: [String])
    case error(String)
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
    @Published var displayName: String?
    @Published var publicId: String?
    @Published var card: VauchiContactCard?
    @Published var contacts: [VauchiContact] = []
    private let contactsPageSize: UInt32 = 20
    @Published var errorMessage: String?
    @Published var syncState: SyncState = .idle
    @Published var lastSyncTime: Date?
    @Published var pendingUpdates: Int = 0

    /// Network state
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

    // Toast state (for undo-able actions like archive/delete)
    @Published var toastMessage: String?
    @Published var toastUndoActionId: String?
    private var toastUndoHandler: (() async throws -> Void)?

    // MARK: - Core-Driven UI

    /// Shared AppViewModel for core-driven screens (Groups, and future tabs).
    /// Created once from VauchiRepository.appEngine — all CoreScreenViews share
    /// this single engine instance (one DB connection, shared cache).
    @Published var coreViewModel: AppViewModel?

    // MARK: - Private Properties

    private var repository: VauchiRepository?
    private var cancellables = Set<AnyCancellable>()
    private let dataDirOverride: String?
    private let relayUrlOverride: String?

    // MARK: - Initialization

    /// Default initializer used by the production app — picks up the
    /// system Application Support data dir and the user's configured
    /// relay URL.
    convenience init() {
        self.init(dataDir: nil, relayUrl: nil)
    }

    /// Test-friendly initializer. `dataDir` lets each test isolate its
    /// own storage; `relayUrl` lets tests point at a local dev relay.
    /// Pass `nil` for either to fall back to production defaults.
    init(dataDir: String?, relayUrl: String?) {
        dataDirOverride = dataDir
        relayUrlOverride = relayUrl
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
            let repo = try VauchiRepository(
                dataDir: dataDirOverride,
                relayUrl: relayUrlOverride ?? SettingsService.shared.relayUrl
            )
            repository = repo
            coreViewModel = AppViewModel(appEngine: repo.appEngine)
            // Hand the engine to BackgroundSyncService so its
            // BGTaskScheduler interval comes from core's
            // PERIODIC_SYNC_INTERVAL_SECONDS rather than a frontend
            // magic number (audit P2-C).
            BackgroundSyncService.shared.setAppEngine(repo.appEngine)
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
                    // Hold on loading state during the constant-time
                    // duress decision so real contacts don't flash if
                    // initializeRepository() set .ready.
                    self?.appState = .loading
                    // Core owns the post-biometric duress decision and
                    // the constant-time floor that hides whether duress
                    // is configured (audit
                    // `2026-04-28-lifecycle-session-residue-umbrella`
                    // P2-B). The call sleeps in Rust for ≥
                    // BIOMETRIC_UNLOCK_MIN_DURATION (300 ms), so dispatch
                    // off main to avoid blocking the UI.
                    let engine = self?.coreViewModel?.appEngine
                    DispatchQueue.global(qos: .userInitiated).async {
                        // ADR-031: biometric success is reported as a
                        // hardware event; core consults its duress state
                        // (padding to BIOMETRIC_UNLOCK_MIN_DURATION) and
                        // returns ActionResult.biometricUnlockOutcome.
                        let resultJson = try? engine?.handleHardwareEvent(event: .biometricUnlockSucceeded)
                        var promptForDuress = false
                        if let resultJson,
                           let data = resultJson.data(using: .utf8),
                           let result = try? coreJSONDecoder.decode(ActionResult.self, from: data),
                           case let .biometricUnlockOutcome(outcome) = result {
                            promptForDuress = (outcome == "PromptForDuressPin")
                        }
                        DispatchQueue.main.async {
                            if promptForDuress {
                                self?.appState = .appPasswordRequired
                            } else {
                                // Unlocked, or no/undecodable outcome —
                                // proceed, matching the prior .none behavior.
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
        // Forward platform reachability into core, which decides
        // banner rendering (via `Component::Banner` injected into
        // every emitted ScreenModel) and auto-sync on reconnect.
        // Frontend just plumbs the platform signal through —
        // no local `isOnline` mirror, no banner switch, no
        // auto-sync closure (audit
        // `2026-04-28-lifecycle-session-residue-umbrella` P2-D).
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                try? self?.coreViewModel?.appEngine.setNetworkOnline(online: isConnected)

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
        try? coreViewModel?.appEngine.setNetworkOnline(online: isOnline)
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
            displayName = try repository.getDisplayName()
            publicId = try repository.getPublicId()
        } catch {
            // Identity not found is expected if not created yet
            displayName = nil
            publicId = nil
        }
    }

    // MARK: - Card

    func loadCard() async {
        guard let repository else { return }

        do {
            card = try repository.getOwnCard()
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

    /// Triggers auto-lock if enabled when app goes to background (C1)
    func handleAppBackgrounded() {
        guard repository?.handleAppBackgrounded() != nil else { return }
        // Core navigated to Lock screen — require re-authentication
        appState = .authenticationRequired
    }

    /// Poll for and display OS notifications (E)
    func pollNotifications() {
        NotificationService.shared.pollAndDisplayNotifications(repository: repository)
    }

    // MARK: - Contacts

    func loadContacts() async {
        guard let repository else { return }

        // Reset pagination

        do {
            let contactsData = try repository.listContactsPaginated(offset: 0, limit: contactsPageSize)
            contacts = contactsData
        } catch {
            contacts = []
        }
    }

    func getContact(id: String) async -> VauchiContact? {
        guard let repository else { return nil }

        do {
            return try repository.getContact(id: id)
        } catch {
            return nil
        }
    }

    // MARK: - Hidden Contacts

    // Based on: features/resistance.feature - R3 Hidden Contact UI

    /// Load hidden contacts
    func loadHiddenContacts() async {
        guard let repository else { return }

        do {
            contacts = try repository.listHiddenContacts()
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

    // MARK: - Contact Notes & Proposal Trust

    /// Save a private note for a contact (never shared).
    func setContactNote(contactId: String, note: String) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.setContactNote(contactId: contactId, note: note)
    }

    /// Load the private note for a contact.
    func getContactNote(contactId: String) async throws -> String? {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        return try repository.getContactNote(contactId: contactId)
    }

    /// Save a private note on a specific field of a contact.
    func setContactFieldNote(contactId: String, fieldId: String, note: String) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.setContactFieldNote(contactId: contactId, fieldId: fieldId, note: note)
    }

    /// Load all private field notes for a contact.
    func getContactFieldNotes(contactId: String) async throws -> [MobileFieldNote] {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        return try repository.getContactFieldNotes(contactId: contactId)
    }

    /// Delete a private note on a specific field of a contact.
    func deleteContactFieldNote(contactId: String, fieldId: String) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.deleteContactFieldNote(contactId: contactId, fieldId: fieldId)
    }

    /// Toggle proposal trust for a contact (local-only flag).
    func setProposalTrusted(contactId: String, trusted: Bool) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.setProposalTrusted(contactId: contactId, trusted: trusted)
    }

    func removeContact(id: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        _ = try repository.removeContact(id: id)
        contacts.removeAll { $0.id == id }
    }

    // MARK: - Contact Lifecycle (archive / soft-delete)

    /// Soft-delete an imported contact (reversible via undo toast).
    func softDeleteImportedContact(id: String) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.softDeleteImportedContact(id: id)
        contacts.removeAll { $0.id == id }
    }

    /// Archive a contact (exchanged contacts — reversible).
    func archiveContact(id: String) async throws {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        try repository.archiveContact(id: id)
        contacts.removeAll { $0.id == id }
    }

    /// Returns the footer-button action id (`"delete_contact"` or
    /// `"archive_contact"`) for the given contact. Views dispatch on
    /// the returned id so they never branch on
    /// `MobileContact.isImported` directly (§1A pure-renderer rule).
    func contactDetailFooterActionId(contactId: String) throws -> String {
        guard let repository else { throw VauchiRepositoryError.notInitialized }
        return try repository.contactDetailFooterActionId(contactId: contactId)
    }

    // MARK: - Toast

    /// Show a toast message with an optional undo handler.
    func showToast(_ message: String, undoHandler: (() async throws -> Void)? = nil) {
        withAnimation {
            toastMessage = message
            toastUndoActionId = undoHandler != nil ? UUID().uuidString : nil
            toastUndoHandler = undoHandler
        }
        let currentMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, toastMessage == currentMessage else { return }
            dismissToast()
        }
    }

    /// Handle undo action from toast.
    func handleUndo() {
        guard let handler = toastUndoHandler else { return }
        let undoHandler = handler
        dismissToast()
        Task {
            do {
                try await undoHandler()
            } catch {
                showError("Undo Failed", message: error.localizedDescription)
            }
        }
    }

    /// Dismiss the current toast.
    func dismissToast() {
        withAnimation {
            toastMessage = nil
            toastUndoActionId = nil
            toastUndoHandler = nil
        }
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

    /// Initialize demo contact if needed (called by `createIdentity`
    /// for new users with no contacts). Core's
    /// `apply_demo_contact_overlay` reads the demo state at render time
    /// and emits the banner — the view-model no longer holds a copy.
    func initDemoContactIfNeeded() async {
        guard let repository else { return }
        do {
            _ = try repository.initDemoContactIfNeeded()
        } catch {
            #if DEBUG
                print("VauchiViewModel: Failed to init demo contact: \(error)")
            #endif
        }
    }

    // MARK: - Visibility Labels

    /// Get all labels for a contact
    func getLabelsForContact(contactId: String) throws -> [VauchiVisibilityLabel] {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.getLabelsForContact(contactId: contactId)
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

    func exportFullBackup(password: String) async throws -> String {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        return try repository.exportFullBackup(password: password)
    }

    func importFullBackup(data: String, password: String) async throws {
        guard let repository else {
            throw VauchiRepositoryError.notInitialized
        }

        try repository.importFullBackup(data: data, password: password)
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
}
