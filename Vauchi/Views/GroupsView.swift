// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// GroupsView.swift
// Phase 1A.5 (core-gui-architecture-alignment): the Contact Groups
// screen is now a thin iOS shell around
// `CoreScreenView(screenName: "Groups")`. Core's `GroupsEngine`
// (see `core/vauchi-app/src/ui/groups_list.rs`) owns the Members/
// Visibility mode toggle, group list, create/rename/delete flows,
// and routes `OpenGroup` into `AppScreen::GroupDetail` (handled
// by `core/vauchi-app/src/ui/group_detail.rs`).
//
// Historical context: the Groups tab in `ContentView.swift` has
// been using `CoreScreenView("Groups")` since ios!283, making this
// shell the same code path as the main tab. Previously the
// `SettingsView` link pointed at a separate 801-line legacy
// GroupsView implementation that shadowed core — that duplication
// is what this migration removes.
//
// Reached from `SettingsView` via `NavigationLink(destination: GroupsView())`,
// so no NavigationView wrapper here (the parent owns navigation).

import SwiftUI

struct GroupsView: View {
    var body: some View {
        CoreScreenView(screenName: "Groups")
    }
}

#Preview {
    NavigationView {
        GroupsView()
    }
    .environmentObject(VauchiViewModel())
}
