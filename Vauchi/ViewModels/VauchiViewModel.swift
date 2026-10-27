// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

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
import SwiftUI
import VauchiPlatform

/// App-level state for device lock handling
enum AppState: Equatable {
    case loading
    case waitingForUnlock // Layer B: protected data unavailable (prewarming)
    case ready // Normal operation
}

@MainActor
class VauchiViewModel: ObservableObject {
    // MARK: - Published State

    @Published var appState: AppState = .loading
    @Published var isLoading = true
    @Published var hasIdentity = false
    @Published var errorMessage: String?

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

    // MARK: - Core-Driven UI

    /// Shared AppViewModel for core-driven screens (Groups, and future tabs).
    /// Created once from VauchiRepository.appEngine — all CoreScreenViews share
    /// this single engine instance (one DB connection, shared cache).
    @Published var coreViewModel: AppViewModel?

    /// Relays an opaque `vauchi://` URI to core as `LinkOpened`. Core decides
    /// the destination (exchange consent, contact detail, device-link join, or a
    /// core-owned error). Shared by `.onOpenURL` and notification taps so both
    /// surfaces route identically.
    func openDeepLink(_ uri: String) {
        guard let coreVM = coreViewModel else {
            showError("Invalid Link",
                      message: "Please unlock Vauchi first, then re-open the link.")
            return
        }
        coreVM.dispatchPresentation(.deepLinkOpened(uri: uri))
    }

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
            let makeRepository = { [dataDirOverride, relayUrlOverride] in
                try VauchiRepository(
                    dataDir: dataDirOverride,
                    relayUrl: relayUrlOverride ?? SettingsService.shared.relayUrl
                )
            }
            // One repository for the app and background sync; an overridden
            // data directory or relay (tests, debug) gets its own.
            let repo = dataDirOverride == nil && relayUrlOverride == nil
                ? try VauchiRepository.shared.get(orMake: makeRepository)
                : try makeRepository()
            repository = repo
            let coreVM = AppViewModel(appEngine: repo.appEngine)
            coreViewModel = coreVM
            coreVM.reportNetworkCost(NetworkMonitor.shared.cost)
            // Hand the engine to BackgroundSyncService so its
            // BGTaskScheduler interval comes from core's
            // PERIODIC_SYNC_INTERVAL_SECONDS rather than a frontend
            // magic number (audit P2-C).
            BackgroundSyncService.shared.setAppEngine(repo.appEngine)
            appState = .ready
            #if DEBUG
                print("VauchiViewModel: repository initialized successfully")
            #endif
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

    private func setupNetworkMonitoring() {
        // Forward platform reachability into Core, which decides
        // presentation updates and auto-sync on reconnect.
        // Frontend just plumbs the platform signal through —
        // no local `isOnline` mirror, no banner switch, no
        // auto-sync closure (audit
        // `2026-04-28-lifecycle-session-residue-umbrella` P2-D).
        NetworkMonitor.shared.$cost
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cost in
                self?.coreViewModel?.reportNetworkCost(cost)
            }
            .store(in: &cancellables)

        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                // Core syncs when the network comes back (vauchi/private#762).
                try? self?.coreViewModel?.appEngine.setNetworkOnline(online: isConnected)
            }
            .store(in: &cancellables)

        isOnline = NetworkMonitor.shared.isConnected
        try? coreViewModel?.appEngine.setNetworkOnline(online: isOnline)
    }

    // MARK: - State Management

    func loadState() {
        // Don't attempt to load if we're waiting for unlock or auth
        if appState == .waitingForUnlock {
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

        // Out-of-band identity creation emits no core event, so nothing
        // re-enters the presentation reducer on its own — force a full
        // rebuild or the shell keeps rendering the pre-identity
        // (onboarding) surface. Production onboarding reaches the home
        // surface through the dispatch response instead.
        coreViewModel?.dispatchPresentation(.presentationInvalidated)

        // Initialize demo contact for new users with no contacts
        await initDemoContactIfNeeded()
    }

    // MARK: - Lifecycle

    /// Reports backgrounding through the generic presentation reducer.
    func dispatchAppBackgrounded() {
        coreViewModel?.dispatchPresentation(.appBackgrounded)
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
}
