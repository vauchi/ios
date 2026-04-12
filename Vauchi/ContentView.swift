// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContentView.swift
// Root navigation for Vauchi iOS app

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared
    @State private var showRestoreSheet = false

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
                            .font(.title)
                            .fontWeight(.bold)
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
                        onComplete: { onboardingDataJson in
                            Task {
                                let name = Self.displayName(from: onboardingDataJson)
                                try? await viewModel.createIdentity(name: name)
                                SettingsService.shared.hasCompletedOnboarding = true
                                viewModel.loadState()
                            }
                        },
                        onStartBackupImport: {
                            showRestoreSheet = true
                        }
                    )
                    .sheet(isPresented: $showRestoreSheet) {
                        RestoreIdentitySheet(onRestoreComplete: {
                            SettingsService.shared.hasCompletedOnboarding = true
                            viewModel.loadState()
                        })
                    }
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
    }

    /// Extract `display_name` from the core onboarding JSON.
    /// Falls back to empty string so identity creation still proceeds.
    static func displayName(from json: String?) -> String {
        guard let data = json?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["display_name"] as? String
        else {
            return ""
        }
        return name
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
    /// Dynamic default: tab 1 (Contacts) when user has contacts, tab 0 (My Card) otherwise
    @State private var selectedTab: Int

    init(hasContacts: Bool = false) {
        _selectedTab = State(initialValue: hasContacts ? 1 : 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label(
                            localizationService.t("nav.myCard"),
                            systemImage: "person.crop.rectangle.fill"
                        )
                    }
                    .tag(0)
                    .accessibilityIdentifier("tab.myCard")

                ContactsView()
                    .tabItem {
                        Label(
                            localizationService.t("nav.contacts"),
                            systemImage: "person.2.fill"
                        )
                    }
                    .tag(1)
                    .accessibilityIdentifier("tab.contacts")

                ExchangeModePicker(switchToContacts: { selectedTab = 1 })
                    .tabItem {
                        Label(
                            localizationService.t("nav.exchange"),
                            systemImage: "qrcode"
                        )
                    }
                    .tag(2)
                    .accessibilityIdentifier("tab.exchange")

                CoreScreenView(screenName: "Groups")
                    .tabItem {
                        Label(
                            localizationService.t("nav.groups"),
                            systemImage: "rectangle.3.group.fill"
                        )
                    }
                    .tag(3)
                    .accessibilityIdentifier("tab.groups")

                MoreView()
                    .tabItem {
                        Label(
                            localizationService.t("nav.more"),
                            systemImage: "ellipsis.circle.fill"
                        )
                    }
                    .tag(4)
                    .accessibilityIdentifier("tab.more")
            }
            .accentColor(.cyan)

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
}

#Preview("No contacts") {
    ContentView()
        .environmentObject(VauchiViewModel())
}

#Preview("With contacts") {
    MainTabView(hasContacts: true)
        .environmentObject(VauchiViewModel())
}
