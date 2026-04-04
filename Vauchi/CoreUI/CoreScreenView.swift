// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenView.swift
// Generic wrapper that renders any core-driven screen via PlatformAppEngine.

import SwiftUI
import VauchiPlatform

/// Renders a core-driven screen by name using its own `AppViewModel`.
///
/// Each `CoreScreenView` creates and owns its own `PlatformAppEngine` instance.
/// This prevents state collision when multiple tabs use ScreenModel rendering
/// (tab A's navigation doesn't clobber tab B's screen).
///
/// Usage:
/// ```swift
/// CoreScreenView(screenName: "Groups")
/// CoreScreenView(screenName: "Settings")
/// ```
struct CoreScreenView: View {
    let screenName: String
    @StateObject private var viewModel = CoreScreenViewModel()

    var body: some View {
        Group {
            if let screen = viewModel.appViewModel?.currentScreen {
                ScreenRendererView(screen: screen, onAction: { action in
                    viewModel.appViewModel?.handleAction(action)
                })
            } else if viewModel.initError != nil {
                // Engine creation failed — show nothing (tab falls back to native)
                EmptyView()
            } else {
                ProgressView("Loading...")
            }
        }
        .task(id: screenName) {
            viewModel.navigateIfNeeded(to: screenName)
        }
        .alert(item: alertBinding) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var alertBinding: Binding<AppViewModel.AlertMessage?> {
        Binding(
            get: { viewModel.appViewModel?.alertMessage },
            set: { viewModel.appViewModel?.alertMessage = $0 }
        )
    }
}

/// Owns a per-screen `AppViewModel` with lazy engine creation.
///
/// Uses `@MainActor` to match AppViewModel's actor isolation.
/// The engine is created once and reused for the lifetime of this view.
@MainActor
private class CoreScreenViewModel: ObservableObject {
    @Published var appViewModel: AppViewModel?
    @Published var initError: String?
    private var currentScreen: String?

    func navigateIfNeeded(to screenName: String) {
        // Lazy init: create engine on first navigation
        if appViewModel == nil, initError == nil {
            do {
                let engine = try AppEngineService.createEngine()
                appViewModel = AppViewModel(appEngine: engine)
            } catch {
                initError = error.localizedDescription
                #if DEBUG
                    print("CoreScreenViewModel: failed to create engine: \(error)")
                #endif
                return
            }
        }

        // Skip re-navigation if already on the right screen
        guard currentScreen != screenName else { return }
        currentScreen = screenName
        appViewModel?.navigateTo(screenJson: "\"\(screenName)\"")
    }
}
