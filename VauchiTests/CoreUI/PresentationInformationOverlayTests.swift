// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Core explains a surface with an `information` overlay that carries a
/// body and no items, and announces it through the context bar's `info`
/// slot (vauchi/private#479). Both are optional on the wire: a batch from
/// an older Core decodes as before.
final class PresentationInformationOverlayTests: XCTestCase {
    func testAnInformationOverlayDecodesItsBody() throws {
        let json = """
        {"kind":"information","title":"Contacts","items":[],
         "body":"Here are the people you have exchanged cards with."}
        """
        let overlay = try JSONDecoder().decode(PresentationOverlay.self, from: Data(json.utf8))

        XCTAssertEqual(overlay.kind, .information)
        XCTAssertEqual(overlay.title, "Contacts")
        XCTAssertEqual(overlay.body, "Here are the people you have exchanged cards with.")
        XCTAssertTrue(overlay.items.isEmpty)
    }

    func testAnOverlayWithoutABodyStillDecodes() throws {
        let json = """
        {"kind":"action_menu","title":"Actions","items":[]}
        """
        let overlay = try JSONDecoder().decode(PresentationOverlay.self, from: Data(json.utf8))

        XCTAssertEqual(overlay.kind, .actionMenu)
        XCTAssertNil(overlay.body)
    }

    func testAContextBarDecodesTheInfoSlotAndItsAbsence() throws {
        let action = """
        {"interaction_id":"presentation.info","label":"Info",
         "accessibility_label":"About this screen","enabled":true}
        """
        let withInfo = try JSONDecoder().decode(
            PresentationContextBar.self,
            from: Data("{\"info\":\(action)}".utf8)
        )
        XCTAssertEqual(withInfo.info?.label, "Info")
        XCTAssertEqual(withInfo.info?.accessibilityLabel, "About this screen")

        let fourSlots = try JSONDecoder().decode(
            PresentationContextBar.self,
            from: Data("{\"primary\":\(action)}".utf8)
        )
        XCTAssertNil(fourSlots.info)
        XCTAssertEqual(fourSlots.primary?.label, "Info")
    }
}
