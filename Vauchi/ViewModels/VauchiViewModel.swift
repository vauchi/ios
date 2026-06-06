// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiViewModel.swift
// App-shell coordinator for the Vauchi iOS app.
//
// Post-G4 (2026-06-06, problem record 2026-05-02-ios-humble-ui-deep-retirement):
// the domain CRUD that the now-retired named views used to drive
// (card field edit, contact notes / lifecycle, recovery trust, backup,
// per-field visibility, social networks, content updates, cert pinning)
// was deleted. Those actions flow through core via `coreViewModel`
// (`AppViewModel` → `PlatformAppEngine`) under the Humble-UI architecture
// (ADR-021/043), so the parallel view-model methods were dead. What
// remains is genuine app-shell concern: lock/auth routing, repository
// bootstrap, network plumbing, identity creation, the contacts-presence
// flag, the alert/toast surfaces, notification polling, and sync.

import Combine
import CoreUIModels
import Foundation
import LocalAuthentication
import SwiftUI
import VauchiPlatform

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
    @Published var contacts: [VauchiContact] = []
    private let contactsPageSize: UInt32 = 20
    @Published var errorMessage: String?
    @Published var syncState: SyncState = .idle

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

            // Identity/card details are core-owned and rendered via
            // `coreViewModel`; the shell only needs the contacts-presence
            // flag (drives the tab layout) once an identity exists.
            if hasIdentity {
                await loadContacts()
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

        // Initialize demo contact for new users with no contacts
        await initDemoContactIfNeeded()
    }

    // MARK: - Lifecycle

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

        do {
            let contactsData = try repository.listContactsPaginated(offset: 0, limit: contactsPageSize)
            contacts = contactsData
        } catch {
            contacts = []
        }
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
            await loadContacts()
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
}
