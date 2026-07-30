// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Main entry point for Vauchi iOS app

import SwiftUI
import VauchiPlatform

@main
struct VauchiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = VauchiViewModel()
    #if DEBUG
        @State private var showBleDiagnostic = false
        @State private var bleDiagAutoTest: String?
        @State private var bleDiagAutoMode: String?
        @State private var showQrDiagnostic = false
        @State private var qrDiagAutoTest: String?
        @State private var showQrTuner = false
        @State private var qrTunerAutoTest: String?
        @State private var showNfcDiagnostic = false
        @State private var nfcDiagAutoTest: String?
        @State private var showUltrasonicDiagnostic = false
        @State private var ultrasonicDiagAutoTest: String?
        @State private var resetForTesting = false
    #endif

    init() {
        // Before anything else: BLE/exchange/sync log::warn!/error! calls
        // in vauchi-app are silent until this installs the os_log backend
        // (2026-06-08-magic-audio-proximity-driver deferred this
        // permanent version).
        initMobileLogging()

        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        NSLog("[Vauchi] Build: v%@ (%@) core=%@", v, b, coreVersion())

        // T2-8: Exclude app data from iCloud/iTunes backup.
        // Vauchi stores encrypted identity keys and contact data locally —
        // these must not leak into unencrypted cloud backups.
        Self.excludeDataFromBackup()

        #if DEBUG
            // Check launch arguments for BLE diagnostic automation
            // Usage: devicectl device process launch ... app.vauchi.ios --ble-test discovery
            // Usage: devicectl device process launch ... app.vauchi.ios --ble-server
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "--ble-test"), idx + 1 < args.count {
                _bleDiagAutoTest = State(initialValue: args[idx + 1])
                _showBleDiagnostic = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --ble-test %@", args[idx + 1])
            } else if args.contains("--ble-server") {
                _bleDiagAutoMode = State(initialValue: "server")
                _showBleDiagnostic = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --ble-server")
            } else if let idx = args.firstIndex(of: "--qr-test"), idx + 1 < args.count {
                _qrDiagAutoTest = State(initialValue: args[idx + 1])
                _showQrDiagnostic = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --qr-test %@", args[idx + 1])
            } else if let idx = args.firstIndex(of: "--qr-tuner"), idx + 1 < args.count {
                _qrTunerAutoTest = State(initialValue: args[idx + 1])
                _showQrTuner = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --qr-tuner %@", args[idx + 1])
            } else if let idx = args.firstIndex(of: "--nfc-test"), idx + 1 < args.count {
                _nfcDiagAutoTest = State(initialValue: args[idx + 1])
                _showNfcDiagnostic = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --nfc-test %@", args[idx + 1])
            } else if let idx = args.firstIndex(of: "--ultrasonic-test"), idx + 1 < args.count {
                _ultrasonicDiagAutoTest = State(initialValue: args[idx + 1])
                _showUltrasonicDiagnostic = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --ultrasonic-test %@", args[idx + 1])
            }

            if args.contains("--reset-for-testing") {
                _resetForTesting = State(initialValue: true)
                NSLog("[Vauchi] Launch arg: --reset-for-testing")
            }
        #endif
        // Register background tasks
        BackgroundSyncService.shared.registerBackgroundTasks()
        #if DEBUG
            print("VauchiApp: background tasks registered")
        #endif

        // Set up the sync handler — delegates the per-tick decision
        // (gate on identity / OHTTP key, honour throttle) to core's
        // `periodicSyncTick` so the 15-min cadence and 3-retry policy
        // live in one place (audit
        // `2026-04-28-lifecycle-session-residue-umbrella` P2-C). The
        // closure constructs a fresh repository when invoked from the
        // BGTask so it is independent of the foreground app lifecycle.
        BackgroundSyncService.shared.setSyncHandler {
            guard let repository = try? VauchiRepository(relayUrl: SettingsService.shared.relayUrl) else {
                return
            }
            // Drive the tick through the engine so policy decisions
            // (15-min interval, retry budget) come from core.
            _ = try? repository.appEngine.periodicSyncTick()

            // Opportunistic content-update cycle (cadence Option 2,
            // `2026-07-03-periodic-mobile-content-update-cadence`):
            // piggyback on this existing background wakeup — no new
            // BGTask. Best-effort; the applied content lands on disk for
            // the next foreground read, so no UI refresh is needed here.
            _ = try? repository.appEngine.runContentUpdateCycle()

            // Poll for notifications (E)
            NotificationService.shared.pollAndDisplayNotifications(repository: repository)
        }
    }

    /// Exclude the app's Documents and Library directories from iCloud/iTunes backup.
    private static func excludeDataFromBackup() {
        let fileManager = FileManager.default
        let urls = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first,
        ]
        for case let url? in urls {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)
        }
    }

    // Screenshot/screen recording prevention (T1-5)
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyOverlay = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(viewModel)
                    .onAppear {
                        // Schedule background sync if enabled
                        if SettingsService.shared.autoSyncEnabled {
                            BackgroundSyncService.shared.scheduleSyncTask()
                        }
                        // A tapped notification routes through the same core
                        // forward path as `.onOpenURL`; core owns the destination.
                        NotificationService.shared.onDeepLinkTapped = { [viewModel] uri in
                            Task { @MainActor in viewModel.openDeepLink(uri) }
                        }
                    }
                #if DEBUG
                    .task {
                        if resetForTesting, !viewModel.hasIdentity {
                            do {
                                try await viewModel.createIdentity(name: "Test User")
                                NSLog("[Vauchi] --reset-for-testing: identity created")
                                viewModel.loadState()
                            } catch {
                                NSLog("[Vauchi] --reset-for-testing: failed: %@", "\(error)")
                            }
                        }
                    }
                #endif
                    .onOpenURL { url in
                        #if DEBUG
                            // Handle diagnostic deep links: vauchi://diagnostic/ble?test=discovery&mode=server
                            if url.host == "diagnostic" {
                                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                                bleDiagAutoTest = components?.queryItems?.first(where: { $0.name == "test" })?.value
                                bleDiagAutoMode = components?.queryItems?.first(where: { $0.name == "mode" })?.value
                                showBleDiagnostic = true
                                NSLog("[Vauchi] Diagnostic deep link: test=%@ mode=%@",
                                      bleDiagAutoTest ?? "nil", bleDiagAutoMode ?? "nil")
                                return
                            }
                        #endif
                        // Forward the raw URI into Core's reducer. Core decides
                        // the destination and returns presentation commands.
                        viewModel.openDeepLink(url.absoluteString)
                    }
                #if DEBUG
                    .fullScreenCover(isPresented: $showBleDiagnostic) {
                        NavigationView {
                            BleDiagnosticView(autoTest: bleDiagAutoTest, autoMode: bleDiagAutoMode)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Close") { showBleDiagnostic = false }
                                    }
                                }
                        }
                    }
                    .fullScreenCover(isPresented: $showQrDiagnostic) {
                        NavigationView {
                            QRDiagnosticView(autoTest: qrDiagAutoTest)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Close") { showQrDiagnostic = false }
                                    }
                                }
                        }
                    }
                    .fullScreenCover(isPresented: $showQrTuner) {
                        NavigationView {
                            QrCameraTunerView(autoTest: qrTunerAutoTest)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Close") { showQrTuner = false }
                                    }
                                }
                        }
                    }
                    .fullScreenCover(isPresented: $showNfcDiagnostic) {
                        NavigationView {
                            NfcDiagnosticView(autoTest: nfcDiagAutoTest)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Close") { showNfcDiagnostic = false }
                                    }
                                }
                        }
                    }
                    .fullScreenCover(isPresented: $showUltrasonicDiagnostic) {
                        NavigationView {
                            DiagnosticView(autoTest: ultrasonicDiagAutoTest)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button("Close") { showUltrasonicDiagnostic = false }
                                    }
                                }
                        }
                    }
                #endif

                // Privacy overlay when app is in background or screen recording
                if showPrivacyOverlay {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .overlay {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                showPrivacyOverlay = newPhase != .active
                if newPhase == .background {
                    viewModel.dispatchAppBackgrounded()
                    // Foreground DispatchSourceTimers do not survive
                    // backgrounding; cancel so we don't fire stale wakeups
                    // when the app resumes (re-armed on `.active` below).
                    WakeupService.shared.cancelPendingWakeup()
                } else if newPhase == .active {
                    // Re-arm the core-owned poll loop cancelled on background:
                    // `onWakeup()` makes core emit the next `ScheduleWakeup`,
                    // restarting the foreground timer (ADR-044 Am2a Option C).
                    viewModel.coreViewModel?.onWakeup()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                if UIScreen.main.isCaptured {
                    showPrivacyOverlay = true
                }
            }
        }
    }
}
