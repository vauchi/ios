// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FaceToFaceExchangeView.swift
// Pair 4b of `_private/docs/problems/2026-04-28-pure-humble-ui-retire-native-screens`.
//
// Pure Humble UI shell — renders the multi-stage face-to-face exchange via
// `CoreScreenView` over the core-owned `MultiStageExchangeEngine`. The
// cycle-thread session lifecycle is owned by `PlatformAppEngine`
// (`after_screen_transition`).
//
// This view holds no domain state, no nav decisions, and no domain types.
// Per ADR-021/043 it only:
//   1. Renders whatever core's current screen says.
//   2. Emits a UserAction("cancel") to core when SwiftUI dismisses the
//      view without core having routed away — core decides what that
//      means (today: the engine's CANCEL handler ends the cycle thread
//      and navigates back).
//
// Brightness + idle-timer presentation moved to core 2026-05-05 (Phase 2b
// of `2026-05-04-exchange-command-screen-presentation`):
// `MultiStageExchangeEngine::screen_entered` emits
// `Command::SetScreenBrightness(Some(0.65))` +
// `Command::SetIdleTimerDisabled(disabled: true)` on screen entry,
// `screen_exited` emits the inverse pair on exit. The frontend's
// `CommandHandler` (Phase 2a) executes the platform calls — the
// `UIScreen.main.brightness` / `UIApplication.shared.isIdleTimerDisabled`
// access lives there with `savedBrightness` snapshot/restore semantics.

import SwiftUI

struct FaceToFaceExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

    var body: some View {
        Group {
            if let coreVM = viewModel.coreViewModel {
                FaceToFaceCoreShell(coreVM: coreVM)
            } else {
                ProgressView("Loading...")
            }
        }
    }
}

/// Inner shell observing `AppViewModel` directly via `@ObservedObject` —
/// without it, SwiftUI would not propagate inner `@Published` updates from
/// `viewModel.coreViewModel` (same root cause `CoreScreenView` documents).
private struct FaceToFaceCoreShell: View {
    @ObservedObject var coreVM: AppViewModel

    var body: some View {
        // Render-only — core has already navigated to multi_stage_exchange
        // (the picker's mode selection routed here). The Exchange tab body
        // (`ExchangeTabContent`) presents/dismisses this wrapper by
        // observing `currentScreen.screenId`, so there is no SwiftUI nav
        // stack to pop and no re-navigation to issue.
        CoreScreenView(renderingCurrentScreen: ())
            .onDisappear {
                // The wrapper disappeared while core is STILL on
                // multi_stage — i.e. the user left (tab switch) without
                // core leading. Emit the engine-level cancel so core can
                // end the cycle thread. If core already moved (screenId
                // changed first), the guard is false and no spurious
                // cancel fires on the next screen.
                if coreVM.currentScreen?.screenId == "multi_stage_exchange" {
                    coreVM.handleAction(.actionPressed(actionId: "cancel"))
                }
            }
    }
}

#Preview {
    FaceToFaceExchangeView()
        .environmentObject(VauchiViewModel())
}
