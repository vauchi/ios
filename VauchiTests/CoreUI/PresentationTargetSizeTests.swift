// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// `ContextCommandBarView` is keyed by `surfaceID` rather than a live
// `PresentationSurface`, so it can be asked to render before that surface's
// `PresentationTokens` have arrived. `PresentationTokens.minimumTargetSize
// (from:)` is the pure fallback decision — Core's token when one is known,
// Apple's own floor (P5, 2026-09-07 review) when it is not — pulled out so
// it is assertable without a view.

@testable import Vauchi
import XCTest

final class PresentationTargetSizeTests: XCTestCase {
    private func tokens(minimumTargetSize: UInt16) -> PresentationTokens {
        PresentationTokens(
            spacingSmall: 4,
            spacingMedium: 8,
            spacingLarge: 16,
            cornerRadius: 12,
            minimumTargetSize: minimumTargetSize
        )
    }

    func testResolvesToTheTokenWhenOneIsKnown() {
        XCTAssertEqual(
            PresentationTokens.minimumTargetSize(from: tokens(minimumTargetSize: 64)),
            64
        )
    }

    func testFallsBackTo48WhenNoSurfaceHasSuppliedTokensYet() {
        XCTAssertEqual(PresentationTokens.minimumTargetSize(from: nil), 48)
    }

    func testTheFallbackIsExposedForCallersThatNeedItDirectly() {
        XCTAssertEqual(PresentationTokens.fallbackMinimumTargetSize, 48)
    }
}
