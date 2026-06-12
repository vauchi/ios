// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Window-move policy for windowed `Component::List` emissions (Track B
/// of `2026-06-11-contacts-list-eager-render-anr`): with a 200-row
/// window and a 50-row prefetch margin, the renderer requests a
/// re-slice when visible rows approach either edge of the loaded
/// window, keeping the visible region inside the new window so row
/// identity holds across the re-slice. Mirrors the Android policy in
/// `ListWindowPrefetch.kt` — the two frontends must move windows
/// identically for core's clamping to behave the same.
final class ListWindowPrefetchTests: XCTestCase {
    func testMidWindowScrollRequestsNothing() {
        XCTAssertNil(
            listWindowTarget(firstVisible: 80, lastVisible: 100, offset: 0, window: 200, totalCount: 500)
        )
    }

    func testApproachingBottomEdgeRequestsForwardWindow() {
        XCTAssertEqual(
            100,
            listWindowTarget(firstVisible: 130, lastVisible: 150, offset: 0, window: 200, totalCount: 500)
        )
    }

    func testForwardRequestClampsToLastFullWindow() {
        XCTAssertEqual(
            300,
            listWindowTarget(firstVisible: 440, lastVisible: 460, offset: 250, window: 200, totalCount: 500)
        )
    }

    func testAtTailNoForwardRequest() {
        XCTAssertNil(
            listWindowTarget(firstVisible: 460, lastVisible: 480, offset: 300, window: 200, totalCount: 500)
        )
    }

    func testApproachingTopEdgeRequestsBackwardWindow() {
        XCTAssertEqual(
            90,
            listWindowTarget(firstVisible: 240, lastVisible: 260, offset: 200, window: 200, totalCount: 500)
        )
    }

    func testBackwardRequestClampsToZero() {
        XCTAssertEqual(
            0,
            listWindowTarget(firstVisible: 60, lastVisible: 80, offset: 50, window: 200, totalCount: 500)
        )
    }

    func testTopOfFirstWindowNoBackwardRequest() {
        XCTAssertNil(
            listWindowTarget(firstVisible: 0, lastVisible: 20, offset: 0, window: 200, totalCount: 500)
        )
    }

    func testUnwindowedEmissionsNeverRequest() {
        XCTAssertNil(
            listWindowTarget(firstVisible: 0, lastVisible: 150, offset: 0, window: 0, totalCount: 0)
        )
    }
}
