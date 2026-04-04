// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenView.swift
// Generic wrapper that renders any core-driven screen via PlatformAppEngine.

import SwiftUI
import VauchiPlatform

/// Renders a core-driven screen by name using the shared `AppViewModel`.
///
/// Uses the shared `coreViewModel` from `VauchiViewModel` (injected via
/// `@EnvironmentObject`). All `CoreScreenView` instances share one
/// `PlatformAppEngine` — one DB connection, one engine cache.
///
/// When this view appears, it navigates the shared engine to `screenName`.
/// The engine's screen caching makes tab switches instant.
///
/// Usage:
/// ```swift
/// CoreScreenView(screenName: "Groups")
/// CoreScreenView(screenName: "Settings")
/// ```
struct CoreScreenView: View {
    let screenName: String
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var currentScreen: String?

    var body: some View {
        Group {
            if let coreVM = viewModel.coreViewModel,
               let screen = coreVM.currentScreen {
                ScreenRendererView(screen: screen, onAction: { action in
                    coreVM.handleAction(action)
                })
            } else {
                ProgressView("Loading...")
            }
        }
        .task(id: screenName) {
            navigateIfNeeded(to: screenName)
        }
        .alert(item: alertBinding) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func navigateIfNeeded(to screen: String) {
        guard currentScreen != screen else { return }
        currentScreen = screen
        viewModel.coreViewModel?.navigateTo(screenJson: "\"\(screen)\"")
    }

    private var alertBinding: Binding<AppViewModel.AlertMessage?> {
        Binding(
            get: { viewModel.coreViewModel?.alertMessage },
            set: { viewModel.coreViewModel?.alertMessage = $0 }
        )
    }
}
