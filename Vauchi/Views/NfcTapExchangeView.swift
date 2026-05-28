// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NfcTapExchangeView.swift
// Phase 4 of `_private/docs/problems/2026-05-19-nfc-exchange-engine-graduation`.
//
// Pure Humble UI shell — renders the NFC (TapTap) exchange via
// `CoreScreenView` over the core-owned `ExchangeEngine`. The 3-phase
// handshake state lives in core's `NfcExchangeFlow`
// (`core/vauchi-app/src/ui/exchange/nfc.rs`); APDU transceive is
// dispatched by `ExchangeCommandHandler` against `NFCExchangeService`'s
// transceive-shim API (Phase 2 of the graduation).
//
// This view holds no domain state, no nav decisions, and no domain
// types. Per ADR-021/043 it only:
//   1. Navigates to `CoreScreenView(screenName: "Exchange")`.
//   2. Pre-selects TapTap on appear by emitting the picker action
//      `UserAction.listItemSelected("category:fun", "mode:tap_tap")`
//      — the core ExchangeEngine routes to `start_taptap_mode`,
//      constructs the `NfcExchangeFlow`, and emits the initial
//      `Command.NfcActivate { payload: key_offer }` (delivered to
//      `ExchangeCommandHandler` which calls
//      `NFCExchangeService.activate`).
//   3. Emits a UserAction("cancel") to core when SwiftUI dismisses the
//      view without core having routed away.
//
// Replaces the legacy `NfcExchangeView` (137 LOC) which owned the
// 3-phase state machine in Swift via `MobileNfcHandshake`. The legacy
// path violated ADR-031 (frontends produce hardware events, core
// produces commands).

import SwiftUI

struct NfcTapExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

    var body: some View {
        Group {
            if let coreVM = viewModel.coreViewModel {
                NfcTapCoreShell(coreVM: coreVM)
            } else {
                ProgressView("Loading...")
            }
        }
    }
}

/// Inner shell observing `AppViewModel` directly via `@ObservedObject` —
/// without it, SwiftUI would not propagate inner `@Published` updates from
/// `viewModel.coreViewModel` (same root cause `CoreScreenView` documents).
private struct NfcTapCoreShell: View {
    @ObservedObject var coreVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        CoreScreenView(screenName: "Exchange")
            .task {
                // Pre-select TapTap so the picker is skipped — emit
                // the same action the mode picker would fire. The
                // engine routes to start_taptap_mode and emits
                // Command.NfcActivate (delivered to
                // ExchangeCommandHandler via the
                // ActionResultEnvelope.commands path).
                coreVM.handleAction(.listItemSelected(
                    componentId: "category:fun",
                    itemId: "mode:tap_tap"
                ))
            }
            .onDisappear {
                // SwiftUI dismissed without core's lead (e.g., user
                // swiped back) — emit the engine-level cancel so core
                // can react. Core decides the next screen.
                if coreVM.currentScreen?.screenId.hasPrefix("exchange_nfc") == true {
                    coreVM.handleAction(.actionPressed(actionId: "cancel"))
                }
            }
            .onChange(of: coreVM.currentScreen?.screenId) { newId in
                // Core moved off NFC exchange — pop the SwiftUI nav
                // stack so the new screen surfaces. Reaction to core's
                // state, not a frontend nav decision.
                if let id = newId, !id.hasPrefix("exchange_nfc"), id != "exchange_mode_selection" {
                    dismiss()
                }
            }
    }
}

#Preview {
    NfcTapExchangeView()
        .environmentObject(VauchiViewModel())
}
