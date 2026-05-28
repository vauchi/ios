// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// HomeView.swift
// Pure Humble UI shell for the My Card tab. Body delegates to
// `CoreScreenView(actionId:)` — core's `MyInfoEngine` (`core/vauchi-app/src/ui/my_info.rs`)
// emits the entire ScreenModel including the sync chrome chip via
// `apply_sync_chrome_overlay` (core 0.51.23+, `core!994`).
//
// `refreshable` is preserved so the native iOS pull-to-refresh gesture
// stays available. It routes through `viewModel.sync()` which carries
// iOS-side orchestration (post-sync contacts reload + toast on
// updated names) that the chrome chip's direct `Vauchi::sync()` call
// does not (yet) trigger.
//
// G1 ratchet 3/16 → 2/16 of
// `_private/docs/problems/2026-05-02-ios-humble-ui-deep-retirement/`.

import SwiftUI

struct HomeView: View {
    /// Opaque canonical tab id from `tabInfo()`, forwarded to the inner
    /// core screen via `NavigateToTab` (ADR-043 Am4) — no domain literal.
    let actionId: String
    @EnvironmentObject var viewModel: VauchiViewModel

    var body: some View {
        CoreScreenView(actionId: actionId)
            .refreshable {
                await viewModel.sync()
            }
    }
}

#Preview {
    HomeView(actionId: "my_info")
        .environmentObject(VauchiViewModel())
}
