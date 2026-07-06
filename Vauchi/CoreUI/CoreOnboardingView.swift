// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core-driven onboarding flow rendered via the shared PlatformAppEngine.

import CoreUIModels
import SwiftUI

#if canImport(VauchiPlatform)
    import VauchiPlatform

    /// Core-driven onboarding flow rendered through the shared
    /// `AppViewModel` (PAE wrapper) — the same engine that drives
    /// every post-identity screen.
    ///
    /// Slice 32c retired the `MobileOnboardingWorkflow` peer object;
    /// the OnboardingEngine state machine lives inside `AppEngine`
    /// and is already driven by `PlatformAppEngine.current_screen_json`
    /// / `handle_action_json` when no identity exists. This view used
    /// to instantiate its own `OnboardingViewModel` wrapping
    /// `MobileOnboardingWorkflow`; that path collected `OnboardingData`
    /// in memory and required the frontend to extract `display_name`
    /// and call `createIdentity` on `Complete`, silently dropping
    /// `selected_groups` + `fields`. The PAE path persists the full
    /// `OnboardingData` atomically in core
    /// (`AppEngine::handle_completion` in vauchi-app).
    ///
    /// See: `_private/docs/problems/2026-05-17-slice-32c-mobile-ui-retirement/`,
    /// ADR-043 Amendment 2 (forthcoming).
    struct CoreOnboardingView: View {
        @EnvironmentObject var viewModel: VauchiViewModel

        /// Invoked once PAE transitions away from the onboarding screen
        /// (i.e., identity exists in core). The host typically calls
        /// `viewModel.loadState()` so `hasIdentity` flips and ContentView
        /// re-renders as `MainTabView`.
        let onIdentityCreated: () -> Void

        /// Bridge for `ExchangeCommand`s emitted during onboarding (e.g.
        /// the `FilePickFromUser` command from the Phase 2B
        /// `restore_backup` path). The host wires this to
        /// `viewModel.coreViewModel?.handleExchangeCommands` so the
        /// FilePickFromUser command lands on the same `pendingFilePick`
        /// state the root `.fileImporter` observes.
        ///
        /// Today `AppViewModel.handleAction` (Phase 2b envelope path)
        /// already calls `handleExchangeCommands` internally, so this
        /// bridge is a defence-in-depth no-op for the onboarding path —
        /// kept on the public API for symmetry with the prior
        /// `OnboardingViewModel.onExchangeCommands` field and to allow
        /// the host to intercept commands if needed.
        var onExchangeCommands: (([CommandDTO]) -> Void)?

        var body: some View {
            Group {
                if let coreVM = viewModel.coreViewModel {
                    CoreOnboardingContent(
                        coreVM: coreVM,
                        onIdentityCreated: onIdentityCreated,
                        onExchangeCommands: onExchangeCommands
                    )
                } else {
                    ProgressView("Loading...")
                }
            }
        }
    }

    /// Inner content view that subscribes directly to `AppViewModel`
    /// (the shared PAE wrapper) via `@ObservedObject`. The split is
    /// required because `coreViewModel` itself is only `@Published`
    /// on `VauchiViewModel` — SwiftUI re-renders when the
    /// `coreViewModel` *reference* changes, not when its inner
    /// `@Published currentScreen` does. Splitting into an inner view
    /// with `@ObservedObject coreVM` fixes that — same pattern as
    /// `CoreScreenContent` in `CoreScreenView.swift`.
    private struct CoreOnboardingContent: View {
        @ObservedObject var coreVM: AppViewModel
        let onIdentityCreated: () -> Void
        var onExchangeCommands: (([CommandDTO]) -> Void)?

        var body: some View {
            ZStack(alignment: .top) {
                Group {
                    if let screen = coreVM.currentScreen {
                        ScreenRendererView(screen: screen, onAction: { action in
                            coreVM.handleAction(action)
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

                // `ActionResult.ShowToast` host: each screen tree needs its
                // own, because the renderer's overlay only serves
                // `Component.ShowToast`
                // (`2026-06-11-ios-onboarding-alert-host-missing`).
                if let message = coreVM.toastMessage {
                    ToastOverlayView(
                        message: message,
                        undoActionId: coreVM.toastUndoActionId,
                        onAction: { coreVM.handleAction($0) },
                        onDismiss: {
                            withAnimation {
                                coreVM.toastMessage = nil
                                coreVM.toastUndoActionId = nil
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .zIndex(100)
                }
            }
            .alert(item: alertBinding) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                // Cold start: ensure PAE's current screen is loaded so
                // the user sees the Onboarding step PAE reports. With
                // no identity, that's `AppScreen::Onboarding` →
                // `OnboardingEngine::current_screen()` →
                // IdentityCheck / DefaultName / etc.
                coreVM.loadScreen()
            }
            .onChange(of: coreVM.currentScreen?.screenId) { newId in
                // PAE transitioned away from onboarding — identity has
                // been written to the DB by `AppEngine::handle_completion`
                // (display name, groups, and per slice 32c S2, fields).
                // Hand control back to ContentView so it re-evaluates
                // `hasIdentity` and renders `MainTabView`.
                //
                // The onboarding screen_ids are an enumerated set
                // owned by `core/vauchi-app/src/ui/onboarding.rs`:
                // `identity_check`, `link_choice`, `default_name`,
                // `groups_setup`, `contact_info`, `what_next`,
                // `backup_password_entry`. Any other id means PAE
                // navigated past Complete (typically `my_info`).
                // TODO(HUMBLE): [D, P1] frontend decides onboarding completion by matching domain screen_ids;
                // core should emit a NavigateTo or onboarding-complete Command
                // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                if let id = newId, !Self.onboardingScreenIds.contains(id) {
                    onIdentityCreated()
                }
            }
        }

        private var alertBinding: Binding<AppViewModel.AlertMessage?> {
            Binding(
                get: { coreVM.alertMessage },
                set: { coreVM.alertMessage = $0 }
            )
        }

        // TODO(HUMBLE): [W, P1] frontend hardcodes domain onboarding screen_ids; core should expose an
        // `isOnboarding` flag or completion Command (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        /// Screen IDs produced by `OnboardingEngine::current_screen()`.
        /// Source: `core/vauchi-app/src/ui/onboarding.rs:173,222,296,334,404,569,581`.
        /// Kept in sync with that set is a structural contract — drift
        /// is caught at the `app_engine_onboarding_completion_tests`
        /// level in core, which exercises the same Step→screen_id
        /// mapping end-to-end.
        private static let onboardingScreenIds: Set<String> = [
            "identity_check",
            "link_choice",
            "default_name",
            "groups_setup",
            "contact_info",
            "what_next",
            "backup_password_entry",
        ]
    }

#endif
