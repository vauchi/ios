// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MoreView.swift
// Pure Humble UI shell: the entire body delegates to
// `CoreScreenView(actionId: "more")` — the typed tab path
// (`NavigateToTab`), mirroring Groups in `ContentView.tabBody`. Core's
// `MoreEngine` emits a `Component::SectionedActionList` grouping 12
// navigation entries into four sections (primary / secondary / data /
// legal) since core 0.51.22 / `core!991` — see the shell-purity
// investigation
// `_private/docs/investigations/2026-05-28-core-screen-composition-surface.md`.
//
// Replaces the previous hand-rolled 3-section list (~110 LOC of
// NavigationLinks + 8 hardcoded English labels). G1 ratchet of
// `2026-05-02-ios-humble-ui-deep-retirement`: 5/16 → 4/16.

import SwiftUI

struct MoreView: View {
    var body: some View {
        CoreScreenView(actionId: "more")
    }
}

#Preview {
    MoreView()
}
