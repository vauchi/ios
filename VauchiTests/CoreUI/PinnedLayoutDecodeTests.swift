// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
@testable import Vauchi
import VauchiPlatform
import XCTest

/// Pins the `Pinned`-layout wire contract on iOS
/// (`2026-06-11-contacts-list-windowing-design`): the contacts screen
/// will arrive with `"layout": "Pinned"` and the list component becomes
/// the screen's scroll host (`ScreenRendererView.isPinned` →
/// `\.listScrollHost` → `ListView` lazy branch).
///
/// Skips while the pinned `vauchi-platform-swift` release predates
/// `ScreenLayout.pinned` — the decoder rejects unknown raw values, so
/// the contract is untestable (and unreachable) until the pin bump;
/// the skip self-resolves at that bump.
final class PinnedLayoutDecodeTests: XCTestCase {
    private func requirePinned() throws -> ScreenLayout {
        guard let pinned = ScreenLayout(rawValue: "Pinned") else {
            throw XCTSkip("vauchi-platform-swift pin predates ScreenLayout.pinned")
        }
        return pinned
    }

    func testPinnedLayoutDecodesOnScreenModel() throws {
        _ = try requirePinned()

        let json = Data("""
        {"screen_id": "contacts", "title": "Contacts", "components": [], "actions": [], "layout": "Pinned"}
        """.utf8)

        let screen = try coreJSONDecoder.decode(ScreenModel.self, from: json)
        XCTAssertEqual("Pinned", screen.layout.rawValue)
    }

    func testLayoutDefaultsToScrollWhenAbsent() throws {
        let json = Data("""
        {"screen_id": "welcome", "title": "Welcome", "components": [], "actions": []}
        """.utf8)

        let screen = try coreJSONDecoder.decode(ScreenModel.self, from: json)
        XCTAssertEqual(ScreenLayout.scroll, screen.layout)
    }
}
