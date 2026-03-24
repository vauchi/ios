// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiApp.swift
// Main entry point for Vauchi iOS app

import SwiftUI
import VauchiPlatform

@main
struct VauchiApp: App {
    @StateObject private var viewModel = VauchiViewModel()
    @State private var deepLinkHandler = DeepLinkHandler()
    @State private var showDeepLinkConsent = false
    @State private var pendingDeepLinkPayload: String?
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
    #endif

    init() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let buildId = Self.binaryBuildDate() ?? "?"
        NSLog("[Vauchi] Build: v%@ (%@) core=%@ buildId=%@", v, b, coreVersion(), buildId)

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
        #endif
        // Register background tasks
        BackgroundSyncService.shared.registerBackgroundTasks()
        print("VauchiApp: background tasks registered")

        // Set up the sync handler
        BackgroundSyncService.shared.setSyncHandler {
            // Get the repository from settings
            guard let repository = try? VauchiRepository(relayUrl: SettingsService.shared.relayUrl) else {
                return
            }

            // Only sync if we have an identity
            guard repository.hasIdentity() else {
                return
            }

            // Perform sync
            _ = try? repository.sync()
        }
    }

    /// Returns the binary's modification date as a compact build ID string.
    private static func binaryBuildDate() -> String? {
        guard let executableURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let date = attrs[.modificationDate] as? Date
        else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
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
                    }
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
                        // Deep link consent gate (SP-9)
                        // NEVER auto-process — always ask the user first
                        let result = deepLinkHandler.handleDeepLink(url: url)
                        switch result {
                        case let .exchangePending(payload):
                            pendingDeepLinkPayload = payload
                            showDeepLinkConsent = true
                        case let .invalid(reason):
                            print("VauchiApp: Invalid deep link: \(reason)")
                            viewModel.showError("Invalid Link",
                                                message: "The link could not be processed: \(reason)")
                        }
                    }
                    .alert("Exchange Request", isPresented: $showDeepLinkConsent) {
                        Button("Accept Exchange") {
                            deepLinkHandler.grantConsent()
                            if let payload = pendingDeepLinkPayload {
                                // Start the exchange flow with proximity verification
                                viewModel.startExchangeWithDeepLink(payload: payload)
                            }
                            pendingDeepLinkPayload = nil
                        }
                        Button("Decline", role: .cancel) {
                            deepLinkHandler.denyConsent()
                            pendingDeepLinkPayload = nil
                        }
                    } message: {
                        Text("Someone shared an exchange link with you. " +
                            "Do you want to proceed with the contact exchange?\n\n" +
                            "Only accept if you trust the source of this link.")
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
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                if UIScreen.main.isCaptured {
                    showPrivacyOverlay = true
                }
            }
        }
    }
}
