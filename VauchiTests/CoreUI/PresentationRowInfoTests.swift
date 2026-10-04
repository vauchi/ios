// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// A row can explain its item (vauchi/private#479): Core sends an optional
/// `info` action named "About <item>", whose overlay holds the text. A row
/// from an older Core has no such key and decodes as before.
final class PresentationRowInfoTests: XCTestCase {
    private func row(_ info: String) throws -> PresentationRow {
        let json = """
        {"title":"Home address","subtitle":null,"detail":null,"icon_token":null,
         "image_data":null,"fallback_text":null,"selected":false,"enabled":true,
         "activation":null,"secondary_actions":[],"controls":[],
         "accessibility":{"label":"Home address","description":null}\(info)}
        """
        return try JSONDecoder().decode(PresentationRow.self, from: Data(json.utf8))
    }

    func testARowDecodesCoresInfoAction() throws {
        let decoded = try row("""
        ,"info":{"interaction_id":"surface.7.interaction.3","label":"Info",
         "accessibility_label":"About Home address","enabled":true}
        """)

        XCTAssertEqual(decoded.info?.interactionID, "surface.7.interaction.3")
        XCTAssertEqual(decoded.info?.accessibilityLabel, "About Home address")
    }

    func testARowFromAnOlderCoreHasNoInfoAction() throws {
        let decoded = try row("")

        XCTAssertNil(decoded.info)
    }
}
