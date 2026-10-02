// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core marks list-dominant screens `pinned`. The shell scrolled only
// `scroll` surfaces, so a Contacts list taller than an iPhone SE grew past
// the bottom edge and took the context bar and the tab bar with it
// (vauchi/private#481). Only a `fixed` surface must hold still: a moving QR
// breaks the peer camera's lock.

@testable import Vauchi
import XCTest

final class PresentationSurfaceScrollingTests: XCTestCase {
    func testAPinnedSurfaceScrollsLikeAScrollSurface() {
        XCTAssertTrue(PresentationSurfaceLayout.scroll.scrollsContent)
        XCTAssertTrue(PresentationSurfaceLayout.pinned.scrollsContent)
    }

    func testOnlyAFixedSurfaceHoldsStill() {
        XCTAssertFalse(PresentationSurfaceLayout.fixed.scrollsContent)
    }
}
