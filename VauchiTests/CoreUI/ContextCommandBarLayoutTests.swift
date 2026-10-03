// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// The context bar sits directly above the tab bar. On devices it read as
// "strange" (vauchi/private#479): an absent slot kept a button-sized hole,
// the launchers were bare icons nobody could name, and the raised Exchange
// button ran into the row. Where each of Core's four slots goes is pure
// enough to assert without rendering, so `ContextCommandBarLayout` holds it
// and this file pins it.

@testable import Vauchi
import XCTest

final class ContextCommandBarLayoutTests: XCTestCase {
    /// `PresentationAction` only decodes, as it does from Core's batch.
    private func action(_ interactionID: String) -> PresentationAction? {
        let json = """
        {"interaction_id":"\(interactionID)","label":"Label",
         "accessibility_label":"Label","enabled":true}
        """
        return try? JSONDecoder().decode(PresentationAction.self, from: Data(json.utf8))
    }

    private func bar(
        back: Bool = false,
        navigation: Bool = false,
        primary: Bool = false,
        secondary: Bool = false
    ) -> PresentationContextBar {
        PresentationContextBar(
            back: back ? action("back") : nil,
            navigation: navigation ? action("navigation") : nil,
            primary: primary ? action("primary") : nil,
            secondary: secondary ? action("secondary") : nil
        )
    }

    private func tab(iconToken: String) -> PresentationNavigationItem {
        PresentationNavigationItem(
            interactionID: "nav.\(iconToken)",
            label: "Destination",
            accessibilityLabel: "Destination",
            iconToken: iconToken,
            selected: false,
            badgeCount: 0
        )
    }

    // MARK: - slots(bar:)

    func testSlotsKeepTheOrderCoreSendsThemIn() {
        XCTAssertEqual(
            ContextCommandBarLayout.slots(
                bar: bar(back: true, navigation: true, primary: true, secondary: true)
            ),
            [.back, .navigation, .primary, .secondary]
        )
    }

    func testAnAbsentSlotIsLeftOutRatherThanHeldOpen() {
        XCTAssertEqual(
            ContextCommandBarLayout.slots(bar: bar(navigation: true, primary: true, secondary: true)),
            [.navigation, .primary, .secondary]
        )
        XCTAssertEqual(
            ContextCommandBarLayout.slots(bar: bar(back: true)),
            [.back]
        )
    }

    /// The launcher opens the same destinations the tab bar shows; two
    /// controls for one list is what readers tripped over.
    func testTheNavigationLauncherIsLeftOutWhileTheNavigationIsOnScreen() {
        let full = bar(back: true, navigation: true, primary: true, secondary: true)

        XCTAssertEqual(
            ContextCommandBarLayout.slots(bar: full, navigationShown: true),
            [.back, .primary, .secondary]
        )
        XCTAssertEqual(
            ContextCommandBarLayout.slots(bar: full, navigationShown: false),
            [.back, .navigation, .primary, .secondary]
        )
    }

    func testNoBarAndABarWithNoActionsDrawNothing() {
        XCTAssertEqual(ContextCommandBarLayout.slots(bar: nil), [])
        XCTAssertEqual(ContextCommandBarLayout.slots(bar: bar()), [])
    }

    // MARK: - showsLabel(_:)

    /// "≡" and "⋯" were never guessed by two of three readers; the chevron
    /// is the platform's own and needs no words.
    func testLaunchersShowTheirLabelAndBackDoesNot() {
        XCTAssertTrue(ContextCommandBarLayout.showsLabel(.navigation))
        XCTAssertTrue(ContextCommandBarLayout.showsLabel(.secondary))
        XCTAssertFalse(ContextCommandBarLayout.showsLabel(.back))
    }

    // MARK: - needsFlexibleGap(slots:)

    /// The primary button fills the row. Without one, a gap in its place
    /// keeps Back at the leading edge and the launchers at the trailing one.
    func testAGapStandsInForAMissingPrimary() {
        XCTAssertTrue(ContextCommandBarLayout.needsFlexibleGap(slots: [.back, .secondary]))
        XCTAssertTrue(ContextCommandBarLayout.needsFlexibleGap(slots: [.back]))
        XCTAssertFalse(ContextCommandBarLayout.needsFlexibleGap(slots: [.back, .primary, .secondary]))
    }

    // MARK: - bottomClearance(above:)

    func testTheRowClearsARaisedCentreAction() {
        let tabs = [tab(iconToken: "person.2"), tab(iconToken: "qrcode"), tab(iconToken: "gearshape")]

        XCTAssertGreaterThan(
            ContextCommandBarLayout.bottomClearance(above: tabs),
            CoreBottomTabBarLayout.centreOverhang
        )
    }

    func testWithoutACentreActionTheRowSitsCloseToTheTabBar() {
        let tabs = [tab(iconToken: "person.2"), tab(iconToken: "gearshape")]

        XCTAssertLessThan(
            ContextCommandBarLayout.bottomClearance(above: tabs),
            CoreBottomTabBarLayout.centreOverhang
        )
        XCTAssertLessThan(
            ContextCommandBarLayout.bottomClearance(above: []),
            CoreBottomTabBarLayout.centreOverhang
        )
    }
}
