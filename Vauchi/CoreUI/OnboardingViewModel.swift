// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// OnboardingViewModel.swift
// Swift wrapper around MobileOnboardingWorkflow (core-driven onboarding)

import Foundation
import SwiftUI

#if canImport(VauchiMobile)
    import VauchiMobile

    /// ViewModel that wraps the core `MobileOnboardingWorkflow` and drives
    /// a `ScreenRendererView` with decoded `ScreenModel` data.
    ///
    /// Usage:
    /// ```swift
    /// @StateObject private var viewModel = OnboardingViewModel()
    ///
    /// ScreenRendererView(
    ///     screen: viewModel.currentScreen,
    ///     onAction: { viewModel.handleAction($0) }
    /// )
    /// ```
    class OnboardingViewModel: ObservableObject {
        @Published var currentScreen: ScreenModel?
        @Published var validationErrors: [String: String] = [:]
        @Published var isComplete = false

        private let workflow: MobileOnboardingWorkflow

        init() {
            workflow = MobileOnboardingWorkflow()
            loadScreen()
        }

        /// Loads the current screen from the core workflow.
        func loadScreen() {
            do {
                let json = try workflow.currentScreenJson()
                guard let data = json.data(using: .utf8) else {
                    print("OnboardingViewModel: failed to convert JSON to Data")
                    return
                }
                currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
                validationErrors = [:]
            } catch {
                print("OnboardingViewModel: failed to load screen: \(error)")
            }
        }

        /// Handles a user action by forwarding it to the core workflow.
        func handleAction(_ action: UserAction) {
            do {
                let actionData = try coreJSONEncoder.encode(action)
                guard let actionJson = String(data: actionData, encoding: .utf8) else {
                    print("OnboardingViewModel: failed to encode action to JSON string")
                    return
                }

                let resultJson = try workflow.handleActionJson(actionJson: actionJson)
                guard let resultData = resultJson.data(using: .utf8) else {
                    print("OnboardingViewModel: failed to convert result JSON to Data")
                    return
                }

                let result = try coreJSONDecoder.decode(ActionResult.self, from: resultData)
                applyResult(result)
            } catch {
                print("OnboardingViewModel: failed to handle action: \(error)")
            }
        }

        /// Returns the collected onboarding data as JSON when the workflow is complete.
        func onboardingDataJson() -> String? {
            try? workflow.onboardingDataJson()
        }

        // MARK: - Private

        private func applyResult(_ result: ActionResult) {
            switch result {
            case let .updateScreen(screen):
                currentScreen = screen
                validationErrors = [:]

            case let .navigateTo(screen):
                currentScreen = screen
                validationErrors = [:]

            case let .validationError(componentId, message):
                validationErrors[componentId] = message

            case .complete:
                isComplete = true
            }
        }
    }

#endif
