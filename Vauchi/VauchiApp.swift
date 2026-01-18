// VauchiApp.swift
// Main entry point for Vauchi iOS app

import SwiftUI

@main
struct VauchiApp: App {
    @StateObject private var viewModel = VauchiViewModel()

    init() {
        // Register background tasks
        BackgroundSyncService.shared.registerBackgroundTasks()

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
        }
    }
}
