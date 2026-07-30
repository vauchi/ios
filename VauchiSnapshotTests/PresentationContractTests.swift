// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

final class PresentationContractTests: XCTestCase {
    func testReducedMotionKeepsOverlayKindsStructurallyDistinct() throws {
        let navigation = try decodeOverlay(kind: "navigation")
        let actions = try decodeOverlay(kind: "action_menu")

        XCTAssertEqual(navigation.kind, .navigation)
        XCTAssertEqual(actions.kind, .actionMenu)
        XCTAssertNotEqual(navigation, actions)
    }

    private func decodeOverlay(kind: String) throws -> PresentationOverlay {
        try JSONDecoder().decode(
            PresentationOverlay.self,
            from: Data("""
            {
              "kind":"\(kind)",
              "title":null,
              "items":[]
            }
            """.utf8)
        )
    }
}
