// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreOnboardingView.swift
// Core-driven onboarding flow using ScreenRendererView + OnboardingViewModel
//
// This view replaces the hardcoded OnboardingView step views with a generic
// renderer driven by core's OnboardingEngine via MobileOnboardingWorkflow.
//
// Currently excluded from the build (see project.yml) because the published
// VauchiMobile bindings don't contain MobileOnboardingWorkflow yet. When
// bindings are updated, swap OnboardingView for CoreOnboardingView in the app.

import SwiftUI

#if canImport(VauchiMobile)
    import VauchiMobile

    /// Core-driven onboarding flow.
    ///
    /// Uses `OnboardingViewModel` to get `ScreenModel` from core and renders
    /// it via `ScreenRendererView`. When the workflow signals completion, the
    /// `onComplete` callback is invoked with the collected onboarding data JSON.
    struct CoreOnboardingView: View {
        @StateObject private var viewModel = OnboardingViewModel()
        let onComplete: (_ onboardingDataJson: String?) -> Void

        var body: some View {
            Group {
                if let screen = viewModel.currentScreen {
                    ScreenRendererView(screen: screen, onAction: { action in
                        viewModel.handleAction(action)
                    })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.3), value: screen.screenId)
                } else {
                    ProgressView("Loading...")
                }
            }
            .onChange(of: viewModel.isComplete) { complete in
                if complete {
                    onComplete(viewModel.onboardingDataJson())
                }
            }
        }
    }

#endif
