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
    private func item(
        interactionID: String = "nav.destination",
        iconToken: String? = "person.2",
        selected: Bool = false,
        badgeCount: UInt32 = 0
    ) -> PresentationNavigationItem {
        PresentationNavigationItem(
            interactionID: interactionID,
            label: "Destination",
            accessibilityLabel: "Destination",
            iconToken: iconToken,
            selected: selected,
            badgeCount: badgeCount
        )
    }

    // MARK: - isCentreAction

    func testTheQrcodeIconedTabIsTheCentreAction() {
        XCTAssertTrue(CoreBottomTabBarLayout.isCentreAction(tab: item(iconToken: "qrcode")))
    }

    func testEveryOtherIconedTabIsNotTheCentreAction() {
        for token in ["person.2", "person.crop.rectangle", "laptopcomputer", "gearshape"] {
            XCTAssertFalse(
                CoreBottomTabBarLayout.isCentreAction(tab: item(iconToken: token)),
                "'\(token)' must not be treated as the raised centre action"
            )
        }
    }

    func testATabWithNoIconTokenIsNotTheCentreAction() {
        XCTAssertFalse(CoreBottomTabBarLayout.isCentreAction(tab: item(iconToken: nil)))
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

    // MARK: - isSelected(tab:)

    /// Selection now arrives on the item itself (`SetNavigation`), not from
    /// a separately-tracked interaction id — so the layout decision is a
    /// direct read of the command's own field.
    func testATabCoreMarksSelectedIsSelected() {
        let tab = item(interactionID: "nav.contacts", iconToken: "person.2", selected: true)

        XCTAssertTrue(CoreBottomTabBarLayout.isSelected(tab: tab))
    }

    func testATabCoreDoesNotMarkSelectedIsNotSelected() {
        let tab = item(interactionID: "nav.contacts", iconToken: "person.2", selected: false)

        XCTAssertFalse(CoreBottomTabBarLayout.isSelected(tab: tab))
    }

    // MARK: - isVisible(items:)

    func testAnEmptyNavigationListIsNotVisible() {
        XCTAssertFalse(CoreBottomTabBarLayout.isVisible(items: []))
    }

    func testANonEmptyNavigationListIsVisible() {
        XCTAssertTrue(CoreBottomTabBarLayout.isVisible(items: [item()]))
    }
}
