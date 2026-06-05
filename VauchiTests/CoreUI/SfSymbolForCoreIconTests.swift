// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Verifies the `sfSymbolForCoreIcon` semantic-token → SF Symbol map,
/// focused on the exchange-mode tokens core emits on the mode-selection
/// screen. An unmapped token must fall back to a stable symbol so a row
/// never renders blank.
final class SfSymbolForCoreIconTests: XCTestCase {
    func testExchangeModeTokensMapToSymbols() {
        XCTAssertEqual(sfSymbolForCoreIcon("qrcode"), "qrcode.viewfinder")
        XCTAssertEqual(sfSymbolForCoreIcon("nfc"), "wave.3.right")
        XCTAssertEqual(sfSymbolForCoreIcon("bump"), "dot.radiowaves.left.and.right")
        XCTAssertEqual(sfSymbolForCoreIcon("shake"), "iphone.radiowaves.left.and.right")
        XCTAssertEqual(sfSymbolForCoreIcon("sparkles"), "wand.and.stars")
        XCTAssertEqual(sfSymbolForCoreIcon("tap"), "hand.tap.fill")
        XCTAssertEqual(sfSymbolForCoreIcon("gesture"), "hand.draw.fill")
        XCTAssertEqual(sfSymbolForCoreIcon("link"), "link")
        XCTAssertEqual(sfSymbolForCoreIcon("cable"), "cable.connector")
    }

    func testUnknownTokenFallsBackToInfoCircle() {
        XCTAssertEqual(sfSymbolForCoreIcon("definitely-not-a-real-icon"), "info.circle")
        XCTAssertEqual(sfSymbolForCoreIcon(""), "info.circle")
    }
}
