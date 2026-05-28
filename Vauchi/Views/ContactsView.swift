// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactsView.swift
// Phase 1A.2 (core-gui-architecture-alignment): the Contacts tab is now
// a thin iOS shell around the core Contacts screen, navigated by the
// opaque tab `action_id` from `tabInfo()` (ADR-043 Am4). Core
// owns the search field, contact list, row actions (archive/hide/delete
// via ListItemAction overflow menu), the "Archived Contacts" and "Find
// Duplicates" screen actions, and the empty-state guidance —
// see `core/vauchi-app/src/ui/contact_list.rs`. Core also emits the
// onboarding demo affordance as a `Component::Banner` via
// `apply_demo_contact_overlay` (core 0.51.20); iOS no longer owns a
// `DemoContactCard` view or the `viewModel.demoContact` gating.
//
// This shell keeps the iOS-specific chrome that isn't part of the
// cross-platform ScreenModel: the NavigationView and a pull-to-refresh
// gesture wired to `viewModel.sync()`.

import CoreUIModels
import SwiftUI

struct ContactsView: View {
    /// Opaque canonical tab id from `tabInfo()`, forwarded to the inner
    /// core screen via `NavigateToTab` (ADR-043 Am4) — no domain literal.
    let actionId: String
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            CoreScreenView(actionId: actionId)
                .navigationTitle(localizationService.t("nav.contacts"))
                .refreshable {
                    await viewModel.sync()
                }
        }
    }
}

#Preview {
    ContactsView(actionId: "contacts")
        .environmentObject(VauchiViewModel())
}
