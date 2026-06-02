// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContentView.swift
// Root navigation for Vauchi iOS app

import SwiftUI
import VauchiPlatform

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
                VStack(spacing: 0) {
                    // Single core-driven content area: renders core's current
                    // screen generically, swapping in the native hardware
                    // wrappers (camera/QR, NFC) for the exchange hardware
                    // screen_ids. Pure Humble UI — no per-tab domain views.
                    MainContentView(coreVM: coreVM)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .refreshable { await viewModel.sync() }

                    Divider()

                    // Custom bottom tab bar. A native `TabView` cannot host N
                    // identical generic `CoreScreenView` tabs — its selection
                    // binding and per-tab lifecycle both break when every tab is
                    // the same view type (verified on device). The humble shell
                    // therefore owns a thin tab bar that just dispatches
                    // `NavigateToTab(action_id)` on tap; labels / icons / ids
                    // all come from core's `tabInfo()`.
                    CoreBottomTabBar(
                        tabs: coreVM.tabs(),
                        selectedId: selectedTabId,
                        accessibilityId: accessibilityId(for:)
                    ) { tab in
                        selectedTabId = tab.id
                        coreVM.navigateToTab(actionId: tab.actionId)
                    }
                }
                .onAppear {
                    navigateToSelectedTab(selectedTabId, coreVM)
                }
            } else {
                ProgressView("Loading...")
            }
        }
    }

    /// Tell core to navigate to the selected tab. `id` is the canonical tab
    /// id; the opaque `action_id` for `NavigateToTab` is looked up from
    /// `tabInfo()`. Used for the initial selection; tab taps navigate via
    /// `CoreBottomTabBar`'s `onTap`.
    private func navigateToSelectedTab(_ id: String, _ coreVM: AppViewModel) {
        guard let tab = coreVM.tabs().first(where: { $0.id == id }) else { return }
        coreVM.navigateToTab(actionId: tab.actionId)
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

/// The single core-driven content area for the main shell. Renders core's
/// current screen generically via the render-only `CoreScreenView`, except
/// for the exchange hardware screens (`multi_stage_exchange`,
/// `exchange_nfc*`) which need native wrappers (camera/QR brightness, NFC
/// reader) presented off `currentScreen.screenId`. Pure Humble UI: one
/// renderer for every tab; the bottom tab bar drives `NavigateToTab`.
/// Observes `AppViewModel` directly so inner `@Published` `currentScreen`
/// updates propagate (same root cause `CoreScreenView` documents).
private struct MainContentView: View {
    @ObservedObject var coreVM: AppViewModel

    /// `screen_id`s rendered by a native hardware wrapper rather than
    /// generically. `multi_stage_exchange` → camera/QR + brightness;
    /// `exchange_nfc*` → NFC reader. Every other screen renders via the
    /// render-only `CoreScreenView`.
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
                CoreScreenView(renderingCurrentScreen: ())
            }
        }
    }
}

/// Custom bottom tab bar rendered from core's `tabInfo()`. Holds no tab
/// domain literals — labels, SF Symbol icons and selection state all come
/// from core. Each item dispatches the tap to the shell, which sets the
/// selection and forwards `NavigateToTab(action_id)` to core. Replaces the
/// native `TabView`, which cannot host N identical generic `CoreScreenView`
/// tabs (its selection binding and per-tab lifecycle break — verified on
/// device).
private struct CoreBottomTabBar: View {
    let tabs: [MobileTabInfo]
    let selectedId: String
    let accessibilityId: (String) -> String
    let onTap: (MobileTabInfo) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                Button {
                    onTap(tab)
                } label: {
                    VStack(spacing: 4) {
                        // Dynamic Type text styles so icon + label scale
                        // with the user's text-size setting. The custom tab
                        // bar replaced the native TabView (whose `.tabItem`
                        // scaled automatically); fixed `.system(size:)` fonts
                        // failed the `.dynamicType` accessibility audit
                        // (AccessibilityUITests.testAccessibilityAudit).
                        Image(systemName: tab.icon)
                            .font(.title2)
                        Text(tab.label)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(tab.id == selectedId ? .cyan : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(accessibilityId(tab.id))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }
}
