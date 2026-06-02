// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContentView.swift
// Root navigation for Vauchi iOS app

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    /// Determines if we should show onboarding
    private var shouldShowOnboarding: Bool {
        // Show onboarding if:
        // 1. No identity exists, OR
        // 2. Identity exists but onboarding wasn't completed (migration scenario)
        if !viewModel.hasIdentity {
            return true
        }
        // If identity exists but onboarding flag not set, they're an existing user
        // who should skip onboarding (migration case)
        if !SettingsService.shared.hasCompletedOnboarding {
            // Auto-mark as complete for existing users
            SettingsService.shared.hasCompletedOnboarding = true
            return false
        }
        return false
    }

    var body: some View {
        Group {
            switch viewModel.appState {
            case .waitingForUnlock:
                WaitingForUnlockView()

            case .authenticationRequired:
                LockScreenView(onUnlock: { viewModel.authenticateAndRetry() })

            case .appPasswordRequired:
                AppPasswordView(viewModel: viewModel)

            default:
                // Existing logic: error / loading / onboarding / ready
                if let error = viewModel.errorMessage {
                    // Show error state prominently for debugging
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
                        Text(localizationService.t("error.generic"))
                            .font(Font.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button(localizationService.t("action.retry")) {
                            viewModel.errorMessage = nil
                            viewModel.loadState()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Dismiss error and reload the app")
                    }
                    .padding()
                } else if viewModel.isLoading {
                    LoadingView()
                } else if shouldShowOnboarding {
                    CoreOnboardingView(
                        onIdentityCreated: {
                            // Slice 32c: PAE owns onboarding end-to-end
                            // — `AppEngine::handle_completion` already
                            // created the identity, persisted groups
                            // and fields, and flipped the
                            // onboarding-complete flag in core. No
                            // frontend `createIdentity` call needed
                            // (and calling it would now double-create).
                            // Refresh `hasIdentity` so this branch
                            // re-evaluates and `MainTabView` takes
                            // over.
                            SettingsService.shared.hasCompletedOnboarding = true
                            viewModel.loadState()
                        },
                        onExchangeCommands: { commands in
                            // Phase 2B `restore_backup` — forward
                            // ExchangeCommands so FilePickFromUser
                            // lands on AppViewModel.pendingFilePick,
                            // which the root `.fileImporter` observes.
                            viewModel.coreViewModel?.handleExchangeCommands(commands)
                        }
                    )
                } else {
                    MainTabView(hasContacts: !viewModel.contacts.isEmpty)
                }
            }
        }
        .onAppear {
            #if DEBUG
                print("ContentView: onAppear, appState=\(viewModel.appState), isLoading=\(viewModel.isLoading), hasIdentity=\(viewModel.hasIdentity), errorMessage=\(String(describing: viewModel.errorMessage))")
            #endif
            viewModel.loadState()
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
        // ADR-031 file-picker host. Applied at ContentView root so the
        // system document picker is reachable from any flow that emits
        // `ExchangeCommand::FilePickFromUser` — including custom-view
        // tabs (MoreView "Import Contacts") that don't render through
        // CoreScreenView, and the Onboarding `restore_backup` path
        // which forwards ExchangeCommands via `onExchangeCommands` into
        // this same `coreViewModel.pendingFilePick` state.
        .corePendingFilePick(viewModel.coreViewModel)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
            Text(LocalizationService.shared.t("sync.syncing"))
                .foregroundColor(.secondary)
                .padding(.top)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared
    /// Default selection: the Contacts tab when the user already has
    /// contacts, otherwise My Card. Keyed on the opaque canonical tab id
    /// that core hands out via `tabInfo()` (ADR-043 Am4) — not a domain
    /// variant.
    @State private var selectedTabId: String

    init(hasContacts: Bool = false) {
        _selectedTabId = State(initialValue: hasContacts ? "contacts" : "my_info")
    }

    var body: some View {
        ZStack(alignment: .top) {
            tabBar

            // Offline banner
            if !viewModel.isOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    Text(localizationService.t("sync.offline_banner"))
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(99)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Offline")
            }

            // Toast overlay for archive/delete undo
            if let message = viewModel.toastMessage {
                HStack(spacing: 12) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if viewModel.toastUndoActionId != nil {
                        Button("Undo") {
                            viewModel.handleUndo()
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.85))
                )
                .padding(.top, 8)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Toast: \(message)")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.toastMessage)
    }

    /// Bottom-tab bar sourced entirely from core's `tabInfo()` — labels,
    /// SF Symbol icons and opaque `action_id`s all come from core, so iOS
    /// holds no hardcoded tab domain literals (ADR-043 Am4). Each tab
    /// body forwards `NavigateToTab(action_id)` on appear.
    private var tabBar: some View {
        Group {
            if let coreVM = viewModel.coreViewModel {
                TabView(selection: $selectedTabId) {
                    ForEach(coreVM.tabs(), id: \.id) { tab in
                        tabBody(for: tab.id)
                            .tabItem {
                                Label(tab.label, systemImage: tab.icon)
                            }
                            .tag(tab.id)
                            .accessibilityIdentifier(accessibilityId(for: tab.id))
                    }
                }
                .accentColor(.cyan)
            } else {
                ProgressView("Loading...")
            }
        }
    }

    /// Route the opaque canonical tab id to its native body. The bodies
    /// are iOS presentation chrome around core screens; routing on the
    /// opaque discriminant is the humble-renderer pattern (like Android's
    /// id→Composable map), not domain branching. `default` renders any
    /// future tab as a plain core screen so a new core tab can't crash.
    @ViewBuilder
    private func tabBody(for id: String) -> some View {
        switch id {
        case "my_info": HomeView(actionId: id)
        case "contacts": ContactsView(actionId: id)
        // S1/S2: exchange is core-driven. `NavigateToTab("exchange")`
        // resolves to core's `exchange_mode_selection` (11-mode picker);
        // selecting a mode drives core to a hardware `screen_id`, which
        // `ExchangeTabView` swaps to the native FaceToFace / NfcTap wrapper.
        case "exchange": ExchangeTabView()
        case "groups": CoreScreenView(actionId: id)
        case "more": MoreView()
        default: CoreScreenView(actionId: id)
        }
    }

    /// Preserve the historical camelCase bottom-tab a11y identifiers
    /// (referenced by manual QA scripts) rather than deriving
    /// "tab.\(id)" from the snake_case canonical id.
    private func accessibilityId(for id: String) -> String {
        switch id {
        case "my_info": "tab.myCard"
        case "contacts": "tab.contacts"
        case "exchange": "tab.exchange"
        case "groups": "tab.groups"
        case "more": "tab.more"
        default: "tab.\(id)"
        }
    }
}

#Preview("No contacts") {
    ContentView()
        .environmentObject(VauchiViewModel())
}

#Preview("With contacts") {
    MainTabView(hasContacts: true)
        .environmentObject(VauchiViewModel())
}

/// Exchange tab body. The exchange flow is core-driven (S1/S2 of
/// `2026-06-02-ios-exchange-flow-core-driven`): the tab root is core's
/// `exchange_mode_selection` picker, and selecting a mode drives core to a
/// hardware `screen_id`. This view observes `currentScreen.screenId` and
/// swaps in the native hardware wrapper (camera/QR brightness, NFC reader)
/// for those ids, rendering every other exchange screen (the picker,
/// BLE/Web/Link modes, delivery status) generically. It is the iOS analogue
/// of android's follow-core effect.
private struct ExchangeTabView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

    var body: some View {
        Group {
            if let coreVM = viewModel.coreViewModel {
                ExchangeTabContent(coreVM: coreVM)
            } else {
                ProgressView("Loading...")
            }
        }
    }
}

/// Inner shell observing `AppViewModel` directly so inner `@Published`
/// `currentScreen` updates propagate (same root cause `CoreScreenView`
/// documents).
private struct ExchangeTabContent: View {
    @ObservedObject var coreVM: AppViewModel

    /// `screen_id`s rendered by a native hardware wrapper rather than
    /// generically. `multi_stage_exchange` → camera/QR + brightness;
    /// `exchange_nfc*` → NFC reader. Every other exchange screen renders
    /// via the render-only `CoreScreenView`.
    private var nativeBody: AnyView? {
        switch coreVM.currentScreen?.screenId {
        case "multi_stage_exchange":
            AnyView(FaceToFaceExchangeView())
        case let id? where id.hasPrefix("exchange_nfc"):
            AnyView(NfcTapExchangeView())
        default:
            nil
        }
    }

    var body: some View {
        Group {
            if let native = nativeBody {
                native
            } else {
                // Render the current exchange screen without navigating.
                CoreScreenView(renderingCurrentScreen: ())
            }
        }
        // Re-assert the exchange tab root on tab entry (mirrors the
        // `.tab(actionId)` re-assert). Kept on the tab body — NOT on the
        // inner per-screen views — so that as core moves between exchange
        // screens (picker → multi_stage → delivery), the inner render-only
        // view does not re-issue `NavigateToTab` and clobber core's screen.
        .task { coreVM.navigateToTab(actionId: "exchange") }
        .onAppear { coreVM.navigateToTab(actionId: "exchange") }
    }
}
