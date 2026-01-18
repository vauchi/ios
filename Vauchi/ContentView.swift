// ContentView.swift
// Root navigation for Vauchi iOS app

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView()
            } else if !viewModel.hasIdentity {
                SetupView()
            } else {
                MainTabView()
            }
        }
        .onAppear {
            viewModel.loadState()
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
