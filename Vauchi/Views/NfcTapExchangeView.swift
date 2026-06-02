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

    var body: some View {
        // Render-only — core has already navigated to exchange_nfc_role.
        // The core mode picker's "Tap tap" selection routed here (and
        // emitted Command.NfcActivate), so this wrapper must NOT re-emit
        // the listItemSelected pre-select (that double-routed under the
        // old NavigationLink entry). The Exchange tab body presents/
        // dismisses this wrapper by observing currentScreen.screenId.
        CoreScreenView(renderingCurrentScreen: ())
            .onDisappear {
                // Wrapper disappeared while core is STILL on the NFC
                // flow — the user left (tab switch) without core leading.
                // Emit the engine-level cancel so core can react. If core
                // already moved, the guard is false (no spurious cancel).
                if coreVM.currentScreen?.screenId.hasPrefix("exchange_nfc") == true {
                    coreVM.handleAction(.actionPressed(actionId: "cancel"))
                }
            }
    }
}

#Preview {
    NfcTapExchangeView()
        .environmentObject(VauchiViewModel())
}
