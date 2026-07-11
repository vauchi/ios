// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// G1 of `_private/docs/problems/2026-05-02-ios-humble-ui-deep-retirement`.
//
// Pure Humble UI shell for the two hardware-exchange screens
// (`multi_stage_exchange`, `exchange_nfc*`). Renders core's current screen
// full-bleed (no back chrome) via the render-only `CoreScreenView`, and emits
// a `cancel` UserAction if SwiftUI dismisses the wrapper while core is STILL
// on the hosted screen — e.g. a tab switch the engine did not lead. If core
// already routed away (screenId changed first), the guard is false and no
// spurious cancel fires.
//
// Unifies the former `FaceToFaceExchangeView` / `NfcTapExchangeView`, which
// were byte-identical apart from which screens they hosted. The hosting
// decision now lives in core: it stamps `native_wrapper_hint` on the
// `ScreenModel`, the shell selects this wrapper from that hint, and the
// wrapper's `Flow` merely mirrors the hint it corresponds to. Per ADR-021/043
// this view holds no domain state, no nav decisions, and no domain types.
//
// Brightness + idle-timer presentation is core-driven
// (`MultiStageExchangeEngine::screen_entered` emits
// `Command::SetScreenBrightness` / `SetIdleTimerDisabled`, the inverse on
// exit) and executed by the platform `CommandHandler` — not here.

import CoreUIModels
import SwiftUI

struct ExchangeHardwareScreen: View {
    /// Which hardware-exchange flow this wrapper hosts. Mirrors the
    /// `NativeWrapperHint` core stamps on the `ScreenModel`; the shell selects
    /// this wrapper from that hint, and the on-dismiss guard compares against it.
    enum Flow {
        /// Multi-stage face-to-face exchange.
        case multiStage
        /// NFC (TapTap) exchange.
        case nfc

        /// The core-emitted hint whose screens this flow's wrapper hosts.
        var wrapperHint: NativeWrapperHint {
            switch self {
            case .multiStage: .multiStageExchange
            case .nfc: .nfcExchange
            }
        }
    }

    /// Observed directly so inner `@Published` `currentScreen` updates
    /// propagate (same root cause `CoreScreenView` documents).
    @ObservedObject var coreVM: AppViewModel
    let flow: Flow

    var body: some View {
        // Render-only — core has already navigated to the hosted screen (the
        // mode picker's selection routed here). The Exchange tab body
        // (`MainContentView`) presents/dismisses this wrapper by observing
        // `currentScreen.screenId`, so there is no SwiftUI nav stack to pop.
        CoreScreenView(renderingCurrentScreen: ())
            .onDisappear {
                if coreVM.currentScreen?.nativeWrapperHint == flow.wrapperHint {
                    // TODO(HUMBLE): [W, P1] frontend hardcodes a generic `cancel` action id;
                    // core should supply the dismiss action id in the ScreenModel
                    // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                    coreVM.handleAction(.actionPressed(actionId: "cancel"))
                }
            }
    }
}

// No #Preview: `AppViewModel` requires a live `PlatformAppEngine`, and this
// render-only wrapper has no visual state of its own to preview — the rendered
// output is `CoreScreenView`'s, already covered by its own snapshots.
