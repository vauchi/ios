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
//   2. Forwards platform-presentation hardware concerns (screen brightness
//      and idle-timer) per ADR-031 §Hardware.
//   3. Emits a UserAction("cancel") to core when SwiftUI dismisses the
//      view without core having routed away — core decides what that
//      means (today: the engine's CANCEL handler ends the cycle thread
//      and navigates back).

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
    @Environment(\.dismiss) var dismiss

    /// Snapshot of system brightness at entry, restored on exit.
    @State private var previousBrightness: CGFloat = 0.5

    var body: some View {
        CoreScreenView(screenName: "MultiStageExchange")
            .onAppear {
                previousBrightness = UIScreen.main.brightness
                // 65% brightness — matches Android. Higher values overexpose
                // the device's own front camera, preventing it from scanning
                // the peer's QR.
                UIScreen.main.brightness = 0.65
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIScreen.main.brightness = previousBrightness
                UIApplication.shared.isIdleTimerDisabled = false

                // SwiftUI dismissed without core's lead (e.g., user swiped
                // back) — emit the engine-level cancel event so core can
                // react. Core decides the next screen.
                if coreVM.currentScreen?.screenId == "multi_stage_exchange" {
                    coreVM.handleAction(.actionPressed(actionId: "cancel"))
                }
            }
            .onChange(of: coreVM.currentScreen?.screenId) { newId in
                // Core moved off multi-stage — pop the SwiftUI nav stack
                // so the new screen surfaces. This is a reaction to
                // core's state, not a frontend nav decision.
                if let id = newId, id != "multi_stage_exchange" {
                    dismiss()
                }
            }
    }
}

#Preview {
    FaceToFaceExchangeView()
        .environmentObject(VauchiViewModel())
}
