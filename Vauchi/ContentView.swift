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
                    OnboardingView()
                } else {
                    MainTabView(hasContacts: !viewModel.contacts.isEmpty)
                }
            }
        }
        .onAppear {
            print("ContentView: onAppear, appState=\(viewModel.appState), isLoading=\(viewModel.isLoading), hasIdentity=\(viewModel.hasIdentity), errorMessage=\(String(describing: viewModel.errorMessage))")
            viewModel.loadState()
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
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
    @ObservedObject private var localizationService = LocalizationService.shared
    /// Dynamic default: tab 1 (Contacts) when user has contacts, tab 0 (Home) otherwise
    @State private var selectedTab: Int

    init(hasContacts: Bool = false) {
        _selectedTab = State(initialValue: hasContacts ? 1 : 0)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(localizationService.t("nav.home"), systemImage: "person.crop.rectangle")
                }
                .tag(0)
                .accessibilityIdentifier("tab.home")

            ContactsView()
                .tabItem {
                    Label(localizationService.t("nav.contacts"), systemImage: "person.2")
                }
                .tag(1)
                .accessibilityIdentifier("tab.contacts")

            FaceToFaceExchangeView(switchToContacts: { selectedTab = 1 })
                .tabItem {
                    Label(localizationService.t("nav.exchange"), systemImage: "qrcode")
                }
                .tag(2)
                .accessibilityIdentifier("tab.exchange")

            SettingsView()
                .tabItem {
                    Label(localizationService.t("nav.settings"), systemImage: "gear")
                }
                .tag(3)
                .accessibilityIdentifier("tab.settings")

            HelpView()
                .tabItem {
                    Label(localizationService.t("nav.help"), systemImage: "questionmark.circle")
                }
                .tag(4)
                .accessibilityIdentifier("tab.help")
        }
        .accentColor(.cyan)
    }
}

#Preview("No contacts") {
    ContentView()
        .environmentObject(VauchiViewModel())
}

#Preview("With contacts") {
    MainTabView(hasContacts: true)
}
