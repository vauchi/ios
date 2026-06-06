// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ExchangeHardwareScreenTests.swift
// Tests for `ExchangeHardwareScreen.Flow.hosts`, the screen-id guard that
// gates the on-dismiss `cancel` emission. The guard exists so a tab switch
// (wrapper dismissed while core is STILL on the exchange screen) cancels the
// flow, while a core-led transition (screenId already changed) does not fire
// a spurious cancel. The unification of `FaceToFaceExchangeView` /
// `NfcTapExchangeView` (problem record 2026-05-02-ios-humble-ui-deep-retirement
// G1) centralised the two flows' only real difference — exact-match vs
// prefix-match — into this enum, so it is pinned here.

@testable import Vauchi
import XCTest

final class ExchangeHardwareScreenTests: XCTestCase {
    func testMultiStageHostsExactScreenOnly() {
        XCTAssertTrue(ExchangeHardwareScreen.Flow.multiStage.hosts("multi_stage_exchange"))
        // Exact match, not prefix — a sibling screen must NOT keep the wrapper
        // hosting (else a core-led transition to it would be read as "still
        // mine" and fire a spurious cancel).
        XCTAssertFalse(ExchangeHardwareScreen.Flow.multiStage.hosts("multi_stage_exchange_done"))
        XCTAssertFalse(ExchangeHardwareScreen.Flow.multiStage.hosts("contacts"))
    }

    func testNfcHostsAllExchangeNfcSubscreens() {
        // Prefix match — the NFC flow spans `exchange_nfc_role`,
        // `exchange_nfc_*` handshake sub-states; all stay hosted by one wrapper.
        XCTAssertTrue(ExchangeHardwareScreen.Flow.nfc.hosts("exchange_nfc"))
        XCTAssertTrue(ExchangeHardwareScreen.Flow.nfc.hosts("exchange_nfc_role"))
        XCTAssertFalse(ExchangeHardwareScreen.Flow.nfc.hosts("multi_stage_exchange"))
        XCTAssertFalse(ExchangeHardwareScreen.Flow.nfc.hosts("exchange"))
    }
}
