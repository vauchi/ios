// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// `PresentationImageFrameSpec` is the pure sizing decision pulled out of
// `image(_:)` so this file can assert the frame Core's optional `size`
// produces without a SwiftUI layout pass — same reasoning
// `AvatarFallbackSpecTests` documents for the fallback-initials sizing.

@testable import Vauchi
import XCTest

final class PresentationImageFrameSpecTests: XCTestCase {
    func testAnExplicitSizeBecomesTheDiameterAndCapsToAvailableWidth() {
        let spec = PresentationImageFrameSpec(size: 88, minimumTarget: 44)

        XCTAssertEqual(spec.diameter, 88)
        XCTAssertTrue(spec.capsToAvailableWidth)
    }

    /// Absent `size` (every avatar) must keep drawing at the surface's
    /// minimum target and flooring rather than capping — the pre-existing
    /// behavior this change must not disturb.
    func testAnAbsentSizeFallsBackToTheMinimumTargetAndDoesNotCap() {
        let spec = PresentationImageFrameSpec(size: nil, minimumTarget: 44)

        XCTAssertEqual(spec.diameter, 44)
        XCTAssertFalse(spec.capsToAvailableWidth)
    }

    func testTheOnboardingMarkSizeDiffersFromTheAvatarMinimumTarget() {
        let onboardingMark = PresentationImageFrameSpec(size: 88, minimumTarget: 44)
        let avatar = PresentationImageFrameSpec(size: nil, minimumTarget: 44)

        XCTAssertNotEqual(onboardingMark, avatar)
    }
}
