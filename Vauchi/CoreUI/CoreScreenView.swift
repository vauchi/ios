// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenView.swift
// Generic wrapper that renders any core-driven screen via PlatformAppEngine.

import SwiftUI
import VauchiPlatform

/// Renders a core-driven screen by name using ScreenRendererView.
///
/// Usage:
/// ```swift
/// CoreScreenView(screenName: "Settings", appViewModel: viewModel)
/// CoreScreenView(screenName: "Contacts", appViewModel: viewModel)
/// ```
///
/// The view navigates to the named screen on appear and renders
/// whatever ScreenModel core returns. All user actions are forwarded
/// to core via AppViewModel. When core emits navigation results,
/// the screen updates automatically.
struct CoreScreenView: View {
    let screenName: String
    @ObservedObject var appViewModel: AppViewModel

    var body: some View {
        Group {
            if let screen = appViewModel.currentScreen {
                ScreenRendererView(screen: screen, onAction: { action in
                    appViewModel.handleAction(action)
                })
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            appViewModel.navigateTo(screenJson: "\"\(screenName)\"")
        }
        .alert(item: $appViewModel.alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
