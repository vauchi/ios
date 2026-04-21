// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// HomeView.swift
// Phase 1A.1 (core-gui-architecture-alignment): the My Card tab is now
// a thin iOS shell around `CoreScreenView(screenName: "my_info")`. Core
// owns field add/edit/delete, avatar, group/entry toggle, preview-as,
// and the first-exchange prompt — see `core/vauchi-app/src/ui/my_info.rs`.
// This shell keeps the iOS-specific chrome (sync toolbar, public-ID
// caption, sync footer captions) that isn't part of the cross-platform
// ScreenModel.

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                Divider()
                CoreScreenView(screenName: "MyInfo")
                syncFooter
            }
            .navigationTitle(localizationService.t("nav.home"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.sync() } }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.syncState == .syncing)
                    .accessibilityIdentifier("home.sync")
                    .accessibilityLabel("Sync")
                    .accessibilityHint("Synchronize your card and contacts with the relay server")
                }
            }
            .refreshable {
                await viewModel.sync()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let publicId = viewModel.identity?.publicId {
                    Text("ID: \(String(publicId.prefix(16)))...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(themeService.textSecondary)
                        .accessibilityLabel("Public ID prefix")
                }
            }
            Spacer()
            SyncStatusIndicator(syncState: viewModel.syncState)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var syncFooter: some View {
        if viewModel.pendingUpdates > 0 || viewModel.lastSyncTime != nil {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.pendingUpdates > 0 {
                    HStack {
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text("\(viewModel.pendingUpdates) pending updates")
                            .font(.caption)
                            .foregroundColor(themeService.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let lastSync = viewModel.lastSyncTime {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(themeService.textSecondary)
                            .accessibilityHidden(true)
                        Text("Last synced: \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(themeService.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

struct SyncStatusIndicator: View {
    let syncState: SyncState

    var body: some View {
        Group {
            switch syncState {
            case .idle:
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            case .syncing:
                ProgressView()
                    .scaleEffect(0.8)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("settings.sync.status")
    }

    private var accessibilityLabel: String {
        switch syncState {
        case .idle: "Sync ready"
        case .syncing: "Syncing in progress"
        case let .success(_, _, _, names) where !names.isEmpty:
            "Sync completed, updated: \(names.joined(separator: ", "))"
        case .success: "Sync completed successfully"
        case .error: "Sync error occurred"
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(VauchiViewModel())
}
