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
                    MainTabView()
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

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(localizationService.t("nav.home"), systemImage: "person.crop.rectangle")
                }

            ContactsView()
                .tabItem {
                    Label(localizationService.t("nav.contacts"), systemImage: "person.2")
                }

            ExchangeView()
                .tabItem {
                    Label(localizationService.t("nav.exchange"), systemImage: "qrcode")
                }

            SettingsView()
                .tabItem {
                    Label(localizationService.t("nav.settings"), systemImage: "gear")
                }
        }
        .accentColor(.cyan)
    }
}

#Preview {
    ContentView()
        .environmentObject(VauchiViewModel())
}
