// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Core sends a list's `style` only when it is not an ordinary list, and as
/// an open string: "buttons" draws the rows as native buttons, while an
/// absent or unrecognised value must still draw rows rather than fail the
/// surface.
///
/// Traces to: features/generic_presentation_protocol.feature
final class PresentationListStyleTests: XCTestCase {
    private func decode(style: String?) throws -> PresentationNode.ListNode {
        let styleField = style.map { "\"style\":\"\($0)\"," } ?? ""
        let json = """
        {"id":"surface.1.exchange_actions","label":null,"rows":[],
         "searchable":false,"paging":null,\(styleField)
         "accessibility":{"label":"","hint":null,"role":null}}
        """
        return try JSONDecoder().decode(PresentationNode.ListNode.self, from: Data(json.utf8))
    }

    func testButtonsStyleDrawsButtons() throws {
        XCTAssertTrue(try decode(style: "buttons").drawsButtons)
    }

    func testAbsentStyleDrawsAnOrdinaryList() throws {
        XCTAssertFalse(try decode(style: nil).drawsButtons)
    }

    func testUnrecognisedStyleFallsBackToAnOrdinaryList() throws {
        XCTAssertFalse(try decode(style: "carousel").drawsButtons)
    }
}
