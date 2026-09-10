// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Option A of the 2026-09-07 familiar-simple-interface review: Exchange
// stays the raised centre action among Core's navigation destinations
// rather than becoming a peer of the rest, and every tab needs standard
// VoiceOver tab-bar semantics (`2026-06-02-ios-custom-tabbar-accessibility`
// — a plain HStack of buttons reads as ungrouped generic buttons, not as a
// tab bar). Both decisions are pure enough to assert without rendering a
// view, so `CoreBottomTabBarLayout` holds them and this file pins them.

@testable import Vauchi
import XCTest

final class CoreBottomTabBarLayoutTests: XCTestCase {
    /// `PresentationAction` only decodes from Core's wire JSON (its
    /// `init(from:)` suppresses the synthesized memberwise initializer), so
    /// fixtures go through the same decoder production code uses.
    private func action(
        interactionID: String = "nav.destination",
        iconToken: String?
    ) -> PresentationAction {
        var wire: [String: Any] = [
            "interaction_id": interactionID,
            "label": "Destination",
            "accessibility_label": "Destination",
            "enabled": true,
            "tone": "standard",
        ]
        if let iconToken {
            wire["icon_token"] = iconToken
        }
        let data = try! JSONSerialization.data(withJSONObject: wire)
        return try! JSONDecoder().decode(PresentationAction.self, from: data)
    }

    // MARK: - isCentreAction

    func testTheQrcodeIconedTabIsTheCentreAction() {
        XCTAssertTrue(
            CoreBottomTabBarLayout.isCentreAction(tab: action(iconToken: "qrcode"))
        )
    }

    func testEveryOtherIconedTabIsNotTheCentreAction() {
        for token in ["person.2", "person.crop.rectangle", "laptopcomputer", "gearshape"] {
            XCTAssertFalse(
                CoreBottomTabBarLayout.isCentreAction(tab: action(iconToken: token)),
                "'\(token)' must not be treated as the raised centre action"
            )
        }
    }

    func testATabWithNoIconTokenIsNotTheCentreAction() {
        XCTAssertFalse(CoreBottomTabBarLayout.isCentreAction(tab: action(iconToken: nil)))
    }

    // MARK: - accessibilityValue(position:of:)

    func testAccessibilityValueIsOneIndexedForVoiceOver() {
        XCTAssertEqual(
            CoreBottomTabBarLayout.accessibilityValue(position: 0, of: 5),
            "tab 1 of 5"
        )
        XCTAssertEqual(
            CoreBottomTabBarLayout.accessibilityValue(position: 4, of: 5),
            "tab 5 of 5"
        )
    }

    func testAccessibilityValueTracksWhateverCountCoreSends() {
        XCTAssertEqual(
            CoreBottomTabBarLayout.accessibilityValue(position: 2, of: 4),
            "tab 3 of 4"
        )
    }

    // MARK: - isSelected(tab:selectedInteractionID:)

    func testATabMatchingTheSelectedInteractionIDIsSelected() {
        let tab = action(interactionID: "nav.contacts", iconToken: "person.2")

        XCTAssertTrue(
            CoreBottomTabBarLayout.isSelected(tab: tab, selectedInteractionID: "nav.contacts")
        )
    }

    func testATabNotMatchingTheSelectedInteractionIDIsNotSelected() {
        let tab = action(interactionID: "nav.contacts", iconToken: "person.2")

        XCTAssertFalse(
            CoreBottomTabBarLayout.isSelected(tab: tab, selectedInteractionID: "nav.settings")
        )
    }

    func testNoSelectionMeansNoTabIsSelected() {
        let tab = action(interactionID: "nav.contacts", iconToken: "person.2")

        XCTAssertFalse(
            CoreBottomTabBarLayout.isSelected(tab: tab, selectedInteractionID: nil)
        )
    }
}
