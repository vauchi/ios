// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiApp.swift
// Main entry point for Vauchi iOS app

import SwiftUI
import VauchiMobile

@main
struct VauchiApp: App {
    @StateObject private var viewModel = VauchiViewModel()
    @State private var deepLinkHandler = DeepLinkHandler()
    @State private var showDeepLinkConsent = false
    @State private var pendingDeepLinkPayload: String?

    init() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        NSLog("[Vauchi] Build: v%@ (%@) core=%@", v, b, coreVersion())
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    // Schedule background sync if enabled
                    if SettingsService.shared.autoSyncEnabled {
                        BackgroundSyncService.shared.scheduleSyncTask()
                    }
                }
                .onOpenURL { url in
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
        }
    }
}
