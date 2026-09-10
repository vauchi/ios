// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
@testable import Vauchi
import XCTest

/// Core sends three action tones; the shell must decode every one and
/// colour it distinctly, so a serious action never looks destructive.
final class PresentationActionToneTests: XCTestCase {
    private func decode(_ tone: String) throws -> PresentationAction {
        let json = """
        {"interaction_id":"verify","label":"Verify","accessibility_label":"Verify",
         "icon_token":null,"enabled":true,"tone":"\(tone)","shortcut":null}
        """
        let decoder = JSONDecoder()
        return try decoder.decode(PresentationAction.self, from: Data(json.utf8))
    }

    func testDecodesSeriousTone() throws {
        XCTAssertEqual(try decode("serious").tone, .serious)
    }

    func testEachToneHasItsOwnColour() throws {
        let colours = try [
            decode("standard"), decode("serious"), decode("destructive"),
        ].map(\.tone.foregroundColor)
        XCTAssertEqual(Set(colours).count, 3)
        XCTAssertEqual(PresentationActionTone.destructive.foregroundColor, .red)
        XCTAssertEqual(PresentationActionTone.serious.foregroundColor, .orange)
    }
}
