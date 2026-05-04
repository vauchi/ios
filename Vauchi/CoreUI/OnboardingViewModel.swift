// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// OnboardingViewModel.swift
// Swift wrapper around MobileOnboardingWorkflow (core-driven onboarding)

import CoreUIModels
import Foundation
import SwiftUI

#if canImport(VauchiPlatform)
    import VauchiPlatform

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
        @Published var postOnboardingDestination: PostOnboardingDestination?

        /// Bridge for `ActionResult.exchangeCommands` ActionResults
        /// (e.g. `FilePickFromUser` emitted by Phase 2B
        /// `restore_backup`). Set by CoreOnboardingView to the host
        /// app's `AppViewModel.handleExchangeCommands` so the system
        /// file importer attached at ContentView root receives the
        /// command. Without this bridge the case below would fall
        /// through and the picker would never open.
        var onExchangeCommands: (([ExchangeCommandDTO]) -> Void)?

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
                    #if DEBUG
                        print("OnboardingViewModel: failed to convert JSON to Data")
                    #endif
                    return
                }
                currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
                validationErrors = [:]
            } catch {
                #if DEBUG
                    print("OnboardingViewModel: failed to load screen: \(error)")
                #endif
            }
        }

        /// Handles a user action by forwarding it to the core workflow.
        func handleAction(_ action: UserAction) {
            do {
                let actionData = try coreJSONEncoder.encode(action)
                guard let actionJson = String(data: actionData, encoding: .utf8) else {
                    #if DEBUG
                        print("OnboardingViewModel: failed to encode action to JSON string")
                    #endif
                    return
                }

                let resultJson = try workflow.handleActionJson(actionJson: actionJson)
                guard let resultData = resultJson.data(using: .utf8) else {
                    #if DEBUG
                        print("OnboardingViewModel: failed to convert result JSON to Data")
                    #endif
                    return
                }

                let result = try coreJSONDecoder.decode(ActionResult.self, from: resultData)
                applyResult(result)
            } catch {
                #if DEBUG
                    print("OnboardingViewModel: failed to handle action: \(error)")
                #endif
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

            case let .completeWith(destination):
                postOnboardingDestination = destination
                isComplete = true

            case let .exchangeCommands(commands):
                // Forward to the host's AppViewModel so the .fileImporter
                // hosted at ContentView root receives the
                // FilePickFromUser command. CoreOnboardingView wires
                // `onExchangeCommands` on appear; without it this
                // becomes a no-op.
                onExchangeCommands?(commands)

            case .openEntryDetail, .showToast,
                 .startDeviceLink, .startBackupImport, .openContact,
                 .editContact, .openUrl, .showAlert, .requestCamera,
                 .wipeComplete, .showFormDialog, .previewAs, .unknown:
                break
            }
        }
    }

#endif
