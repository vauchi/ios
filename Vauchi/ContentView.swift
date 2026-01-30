// ContentView.swift
// Root navigation for Vauchi iOS app

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

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
            if let error = viewModel.errorMessage {
                // Show error state prominently for debugging
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("Initialization Error")
                        .font(.title)
                        .fontWeight(.bold)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        viewModel.errorMessage = nil
                        viewModel.loadState()
                    }
                    .buttonStyle(.borderedProminent)
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
        .onAppear {
            print("ContentView: onAppear, isLoading=\(viewModel.isLoading), hasIdentity=\(viewModel.hasIdentity), errorMessage=\(String(describing: viewModel.errorMessage))")
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
            Text("Loading...")
                .foregroundColor(.secondary)
                .padding(.top)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "person.crop.rectangle")
                }

            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }

            ExchangeView()
                .tabItem {
                    Label("Exchange", systemImage: "qrcode")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .accentColor(.cyan)
    }
}

#Preview {
    ContentView()
        .environmentObject(VauchiViewModel())
}
