// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for NotificationService deep-link extraction (record 7 frontend residual).
// Based on: features/notifications.feature - tap notification opens contact detail.
// The tap-forward + cold-launch buffer is integration-verified on device; the
// core-supplied `deep_link_uri` parsing is the frontend-specific unit under test.

@testable import Vauchi
import XCTest

final class NotificationServiceDeepLinkTests: XCTestCase {
    /// Scenario: a displayed notification carried core's `vauchi://contact/<id>`
    /// tap target, so the tap handler recovers exactly that URI to relay to core.
    func testDeepLinkUriExtractedFromUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            "contact_id": "abc123",
            "event_key": "card_update:abc123",
            "deep_link_uri": "vauchi://contact/abc123",
        ]

        XCTAssertEqual(
            NotificationService.deepLinkUri(from: userInfo),
            "vauchi://contact/abc123"
        )
    }

    /// Scenario: a notification without a tap target (older payload) yields no
    /// URI, so the tap opens the app without forwarding a spurious link to core.
    func testDeepLinkUriAbsentReturnsNil() {
        let userInfo: [AnyHashable: Any] = [
            "contact_id": "abc123",
            "event_key": "card_update:abc123",
        ]

        XCTAssertNil(NotificationService.deepLinkUri(from: userInfo))
    }

    /// Scenario: a malformed (non-string) value is rejected rather than crashing
    /// the tap handler on a force-cast.
    func testDeepLinkUriNonStringReturnsNil() {
        let userInfo: [AnyHashable: Any] = ["deep_link_uri": 42]

        XCTAssertNil(NotificationService.deepLinkUri(from: userInfo))
    }
}
