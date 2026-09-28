// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for NotificationService's contextual OS authorization
// (vauchi/private#278, Problem 1): permission is asked for at the moment the
// first notification is about to be shown — not at launch — and a notification
// the user has not allowed is dropped silently.
// Based on: features/notifications.feature - notification presentation.

import UserNotifications
@testable import Vauchi
import XCTest

final class NotificationServiceAuthorizationTests: XCTestCase {
    /// Stands in for `UNUserNotificationCenter`, which unit tests cannot
    /// drive. Answers synchronously so no test waits on a clock.
    private final class AuthorizerSpy: NotificationAuthorizing {
        let status: UNAuthorizationStatus
        let grantsRequest: Bool
        private(set) var requestCount = 0

        init(status: UNAuthorizationStatus, grantsRequest: Bool = false) {
            self.status = status
            self.grantsRequest = grantsRequest
        }

        func currentStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
            completion(status)
        }

        func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
            requestCount += 1
            completion(grantsRequest)
        }
    }

    private let notification = NotificationService.PreparedNotification(
        title: "Card updated",
        body: "Alice updated her card",
        eventKey: "card_update:abc123",
        deepLinkUri: "vauchi://contact/abc123",
        osCategoryId: "card_update",
        osCategoryOptions: []
    )

    private func delivered(with authorizer: AuthorizerSpy) -> [String] {
        var keys: [String] = []
        NotificationService.deliverIfAuthorized(notification, authorizer: authorizer) {
            keys.append($0.eventKey)
        }
        return keys
    }

    func testAuthorizedDeliversWithoutAsking() {
        let authorizer = AuthorizerSpy(status: .authorized)

        XCTAssertEqual(delivered(with: authorizer), ["card_update:abc123"])
        XCTAssertEqual(authorizer.requestCount, 0)
    }

    func testUndecidedAsksOnceAndDeliversWhenGranted() {
        let authorizer = AuthorizerSpy(status: .notDetermined, grantsRequest: true)

        XCTAssertEqual(delivered(with: authorizer), ["card_update:abc123"])
        XCTAssertEqual(authorizer.requestCount, 1)
    }

    func testUndecidedAsksOnceAndDropsWhenDeclined() {
        let authorizer = AuthorizerSpy(status: .notDetermined, grantsRequest: false)

        XCTAssertEqual(delivered(with: authorizer), [])
        XCTAssertEqual(authorizer.requestCount, 1)
    }

    func testDeniedDropsWithoutAsking() {
        let authorizer = AuthorizerSpy(status: .denied)

        XCTAssertEqual(delivered(with: authorizer), [])
        XCTAssertEqual(authorizer.requestCount, 0)
    }

    func testProvisionalDeliversWithoutAsking() {
        let authorizer = AuthorizerSpy(status: .provisional)

        XCTAssertEqual(delivered(with: authorizer), ["card_update:abc123"])
        XCTAssertEqual(authorizer.requestCount, 0)
    }
}
