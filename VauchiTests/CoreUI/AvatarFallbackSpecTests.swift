// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// `PresentationImageContent` used to size its fallback initials from a
// hardcoded constant rather than the token Core sends
// (`surface.tokens.minimumTargetSize`), and clipped a `Circle()` around a
// `Text` with no fill. `AvatarFallbackSpec` is the pure sizing decision
// pulled out of the view so both can be asserted without rendering:
// `PresentationImageContentTests` covers the pixels, this file covers the
// numbers.

@testable import Vauchi
import XCTest

final class AvatarFallbackSpecTests: XCTestCase {
    func testCarriesTheInitialsAndDiameterItWasGiven() {
        let spec = AvatarFallbackSpec(initials: "TU", diameter: 44)

        XCTAssertEqual(spec.initials, "TU")
        XCTAssertEqual(spec.diameter, 44)
    }

    func testDiameterTracksWhateverTokenTheSurfaceSupplies() {
        let compact = AvatarFallbackSpec(initials: "AB", diameter: 44)
        let comfortable = AvatarFallbackSpec(initials: "AB", diameter: 64)

        XCTAssertNotEqual(compact.diameter, comfortable.diameter)
    }

    /// Core sends whatever text it computed; the spec passes it through
    /// rather than re-deriving initials from a name, which would be the
    /// shell inventing a domain rule ADR-066 reserves to Core.
    func testInitialsPassThroughUnmodifiedIncludingMultiCharacterAndEmpty() {
        XCTAssertEqual(AvatarFallbackSpec(initials: "M", diameter: 48).initials, "M")
        XCTAssertEqual(AvatarFallbackSpec(initials: "TU", diameter: 48).initials, "TU")
        XCTAssertEqual(AvatarFallbackSpec(initials: "", diameter: 48).initials, "")
    }
}
