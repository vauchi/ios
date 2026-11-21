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

    /// Core names the way out of an overlay in the person's language; an
    /// older Core sends none and the shell keeps its own word.
    func testAnOverlayNamesItsCloseWithCoresLabel() throws {
        let current = """
        {"kind":"information","title":"Kontakte","items":[],
         "body":"Text.","close_label":"Schließen"}
        """
        let overlay = try JSONDecoder().decode(PresentationOverlay.self, from: Data(current.utf8))
        XCTAssertEqual(overlay.closeLabel, "Schließen")
        XCTAssertEqual(overlay.closeAccessibilityLabel, "Schließen")

        let older = """
        {"kind":"action_menu","title":"Actions","items":[]}
        """
        let olderOverlay = try JSONDecoder().decode(PresentationOverlay.self, from: Data(older.utf8))
        XCTAssertNil(olderOverlay.closeLabel)
        XCTAssertEqual(olderOverlay.closeAccessibilityLabel, "Close")
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

    /// Core pins a few actions under the content for a decision that must
    /// not scroll away (vauchi/private#1304). A Core that predates the
    /// slot sends none.
    func testAContextBarDecodesItsPinnedActionsInOrderAndTheirAbsence() throws {
        func action(_ index: Int, _ label: String) -> String {
            """
            {"interaction_id":"surface.7.context.presentation.pinned.\(index)","label":"\(label)",
             "accessibility_label":"\(label)","enabled":true}
            """
        }
        let yes = action(0, "Start a new connection")
        let no = action(1, "Leave it")
        let pinning = try JSONDecoder().decode(
            PresentationContextBar.self,
            from: Data("{\"pinned\":[\(yes),\(no)]}".utf8)
        )
        XCTAssertEqual(pinning.pinnedActions.map(\.label), ["Start a new connection", "Leave it"])
        XCTAssertEqual(
            pinning.pinnedActions.map(\.interactionID),
            ["surface.7.context.presentation.pinned.0", "surface.7.context.presentation.pinned.1"]
        )

        let older = try JSONDecoder().decode(
            PresentationContextBar.self,
            from: Data("{\"primary\":\(yes)}".utf8)
        )
        XCTAssertEqual(older.pinnedActions, [])
    }
}
