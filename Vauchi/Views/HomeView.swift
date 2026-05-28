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

import CoreUIModels
import SwiftUI

struct HomeView: View {
    /// Opaque canonical tab id from `tabInfo()`, forwarded to the inner
    /// core screen via `NavigateToTab` (ADR-043 Am4) — no domain literal.
    let actionId: String
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared
    @ObservedObject private var themeService = ThemeService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                Divider()
                CoreScreenView(actionId: actionId)
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
            // The public-ID prefix is a developer-only affordance — it's
            // a stable identity correlator visible to anyone in shoulder
            // range and meaningless to end users. Gated behind DEBUG so
            // it doesn't leak to release. If a release surface is ever
            // needed, place it inside Settings → About (where the
            // version is already shown) rather than the home header.
            // See _private/docs/problems/2026-05-21-ios-shell-issues-
            // from-walkthrough item 2.
            //
            // Sync status indicator retired here: core's
            // apply_sync_chrome_overlay (core!994, core 0.51.23+) now
            // emits a Component::Indicator { id: "sync", … } on every
            // top-level screen, which CoreScreenView renders natively
            // via IndicatorView (vauchi-platform-swift!60 + ios!466).
            // See _private/docs/designs/2026-05-28-sync-chrome-overlay-design.md.
            #if DEBUG
                VStack(alignment: .leading, spacing: 4) {
                    if let publicId = viewModel.publicId {
                        Text("ID: \(String(publicId.prefix(16)))...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeService.textSecondary)
                            .accessibilityLabel("Public ID prefix")
                    }
                }
            #endif
            Spacer()
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

#Preview {
    HomeView(actionId: "my_info")
        .environmentObject(VauchiViewModel())
}
