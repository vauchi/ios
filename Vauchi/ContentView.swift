// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        Group {
            switch viewModel.appState {
            case .waitingForUnlock:
                WaitingForUnlockView()
            case .authenticationRequired:
                LockScreenView(onUnlock: viewModel.authenticateAndRetry)
            case .appPasswordRequired:
                AppPasswordView(viewModel: viewModel)
            default:
                applicationBody
            }
        }
        .onAppear {
            viewModel.loadState()
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
        .corePendingFilePick(viewModel.coreViewModel)
    }

    @ViewBuilder
    private var applicationBody: some View {
        if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(ThemeService.shared.error)
                    .accessibilityHidden(true)
                Text(localizationService.t("error.generic"))
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Button(localizationService.t("action.retry")) {
                    viewModel.errorMessage = nil
                    viewModel.loadState()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if viewModel.isLoading {
            LoadingView()
        } else if let coreViewModel = viewModel.coreViewModel {
            PresentationHostView(viewModel: coreViewModel)
                .refreshable {
                    await viewModel.sync()
                }
        } else {
            LoadingView()
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
