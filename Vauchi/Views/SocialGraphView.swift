// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SocialGraphView.swift
// Pure Humble UI shell — the Contact Network screen renders entirely
// from core's `SocialGraphEngine` (`core/vauchi-app/src/ui/social_graph.rs`).
// Core owns the network summary, trust-level filter chip row, and
// per-trust-level contact sections; tapping a contact emits
// `OpenContact`, which `AppEngine` routes to ContactDetail. No iOS
// routing or domain types needed.
//
// Reached from `SettingsView` via
// `NavigationLink(destination: SocialGraphView())`, so no NavigationView
// wrapper here (the parent owns navigation).

import SwiftUI

struct SocialGraphView: View {
    var body: some View {
        CoreScreenView(screenName: "social_graph")
    }
}

#Preview {
    NavigationView {
        SocialGraphView()
    }
    .environmentObject(VauchiViewModel())
}
