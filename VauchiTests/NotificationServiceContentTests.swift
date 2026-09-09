// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for NotificationService OS-content assembly (RG-11 Humble UI).
// Based on: features/notifications.feature - notification presentation.
// Core owns the OS category decision (`os_category_id`); the shell only
// copies it onto the `UNNotificationContent`, never derives it from a
// domain category.

import UserNotifications
@testable import Vauchi
import XCTest

final class NotificationServiceContentTests: XCTestCase {
    /// Scenario: core attached `os_category_id`, so the delivered content
    /// carries exactly that identifier without shell-side interpretation.
    func testContentCarriesCoreSuppliedOsCategoryId() {
        let content = NotificationService.notificationContent(for: .init(
            title: "Emergency",
            body: "Alice needs help",
            contactId: "abc123",
            eventKey: "emergency_alert:abc123",
            deepLinkUri: "vauchi://contact/abc123",
            osCategoryId: "emergency_alert"
        ))

        XCTAssertEqual(content.categoryIdentifier, "emergency_alert")
        XCTAssertEqual(content.title, "Emergency")
        XCTAssertEqual(content.body, "Alice needs help")
    }

    /// Scenario: the tap target core supplied survives the round trip so
    /// `deepLinkUri(from:)` recovers it at tap time.
    func testContentStashesDeepLinkAndCorrelationKeys() {
        let content = NotificationService.notificationContent(for: .init(
            title: "Card update",
            body: "Bob updated their card",
            contactId: "bob",
            eventKey: "card_update:bob",
            deepLinkUri: "vauchi://contact/bob",
            osCategoryId: "card_update"
        ))

        XCTAssertEqual(NotificationService.deepLinkUri(from: content.userInfo), "vauchi://contact/bob")
        XCTAssertEqual(content.userInfo["contact_id"] as? String, "bob")
        XCTAssertEqual(content.userInfo["event_key"] as? String, "card_update:bob")
    }

    /// Scenario: a notification without a tap target stashes no deep link,
    /// so the tap handler opens the app without forwarding a spurious URI.
    func testContentWithoutDeepLinkOmitsKey() {
        let content = NotificationService.notificationContent(for: .init(
            title: "Contact added",
            body: "Carol",
            contactId: "carol",
            eventKey: "contact_added:carol",
            deepLinkUri: nil,
            osCategoryId: "contact_added"
        ))

        XCTAssertNil(NotificationService.deepLinkUri(from: content.userInfo))
    }

    /// Scenario: the registered OS categories are the ids core emits, so a
    /// core-supplied `os_category_id` always resolves to a registered
    /// category (custom-dismiss reporting for emergencies included).
    func testRegisteredCategoriesUseCoreOsCategoryIds() {
        let categories = NotificationService.osCategories()
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.identifier, $0) })

        XCTAssertEqual(byId["emergency_alert"]?.options, .customDismissAction)
        XCTAssertEqual(byId["contact_added"]?.options, [])
    }
}
