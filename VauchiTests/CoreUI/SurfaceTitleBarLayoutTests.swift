// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core's context bar used to draw as its own row above the tab bar; on an
// iPhone SE it cost 77pt, the largest single block on an exchange screen,
// and left Hover's camera and tab bar off the bottom of the screen
// (vauchi/private#479, #513, #532, 2026-10-06 design). The bar is retired:
// back and info/secondary now draw inline in the surface's own title row,
// the way every platform already puts them, and `primary` moves to a
// full-width button at the bottom of the surface's content instead.
// `SurfaceTitleBarLayout`/`SurfacePrimaryButtonLayout` hold the pure
// placement decisions so they are assertable without rendering.

@testable import Vauchi
import XCTest

final class SurfaceTitleBarLayoutTests: XCTestCase {
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
        secondary: Bool = false,
        info: Bool = false
    ) -> PresentationContextBar {
        PresentationContextBar(
            back: back ? action("back") : nil,
            navigation: navigation ? action("navigation") : nil,
            primary: primary ? action("primary") : nil,
            secondary: secondary ? action("secondary") : nil,
            info: info ? action("info") : nil
        )
    }

    // MARK: - leadingSlots(bar:navigationShown:)

    func testBackLeadsTheTitleRowTheWayThePlatformsBackChevronDoes() {
        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: bar(back: true), navigationShown: false),
            [.back]
        )
    }

    /// The launcher opens the same destinations the tab bar shows; two
    /// controls for one list is what readers tripped over (#479).
    func testTheNavigationLauncherIsLeftOutWhileTheTabBarShowsTheSameList() {
        let full = bar(back: true, navigation: true)

        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: full, navigationShown: true),
            [.back]
        )
        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: full, navigationShown: false),
            [.back, .navigation]
        )
    }

    func testAnAbsentLeadingSlotIsLeftOutRatherThanHeldOpen() {
        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: bar(navigation: true), navigationShown: false),
            [.navigation]
        )
        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: bar(), navigationShown: false),
            []
        )
    }

    func testNoBarLeadsToNoLeadingSlots() {
        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: nil, navigationShown: false),
            []
        )
    }

    // MARK: - trailingSlots(bar:)

    /// Info sits beside Actions, Actions at the trailing-most end — the
    /// canvas's `[ⓘ] [⋯]` ordering (#479 design, 2026-10-06).
    func testInfoComesBeforeActionsAtTheTrailingEnd() {
        XCTAssertEqual(
            SurfaceTitleBarLayout.trailingSlots(bar: bar(secondary: true, info: true)),
            [.info, .secondary]
        )
    }

    func testAnAbsentTrailingSlotIsLeftOutRatherThanHeldOpen() {
        XCTAssertEqual(
            SurfaceTitleBarLayout.trailingSlots(bar: bar(secondary: true)),
            [.secondary]
        )
        XCTAssertEqual(
            SurfaceTitleBarLayout.trailingSlots(bar: bar(info: true)),
            [.info]
        )
        XCTAssertEqual(
            SurfaceTitleBarLayout.trailingSlots(bar: bar()),
            []
        )
    }

    func testNoBarLeadsToNoTrailingSlots() {
        XCTAssertEqual(
            SurfaceTitleBarLayout.trailingSlots(bar: nil),
            []
        )
    }

    /// `primary` is never a title-row slot: it moves to the bottom of the
    /// surface's content instead (`SurfacePrimaryButtonLayout`).
    func testPrimaryIsNeverATitleRowSlot() {
        let full = bar(back: true, navigation: true, primary: true, secondary: true, info: true)

        XCTAssertEqual(
            SurfaceTitleBarLayout.leadingSlots(bar: full, navigationShown: false) +
                SurfaceTitleBarLayout.trailingSlots(bar: full),
            [.back, .navigation, .info, .secondary]
        )
    }

    // MARK: - SurfacePrimaryButtonLayout.pinsToBottom(scrollsContent:)

    /// A fixed surface never scrolls, so only pinning the button itself
    /// keeps it in view regardless of how little content sits above it.
    func testAFixedSurfacePinsThePrimaryButtonToTheBottom() {
        XCTAssertTrue(SurfacePrimaryButtonLayout.pinsToBottom(scrollsContent: false))
    }

    /// A scrolling surface lets the button follow the last row instead —
    /// the design's "pin it under the content".
    func testAScrollingSurfaceLetsThePrimaryButtonFollowTheContent() {
        XCTAssertFalse(SurfacePrimaryButtonLayout.pinsToBottom(scrollsContent: true))
    }
}
