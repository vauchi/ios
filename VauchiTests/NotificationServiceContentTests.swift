// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for NotificationService OS-content assembly (RG-11 Humble UI).
// Based on: features/notifications.feature - notification presentation.
// Core owns the OS category decision (`os_category_id` plus the
// `os_category_options` tokens); the shell copies the id onto the
// `UNNotificationContent`, registers the category from the tokens, and
// stashes only the core-supplied tap target — never a domain field.

import UserNotifications
@testable import Vauchi
import XCTest

final class NotificationServiceContentTests: XCTestCase {
    private func prepared(
        deepLinkUri: String? = "vauchi://contact/abc123",
        osCategoryId: String = "emergency_alert",
        osCategoryOptions: [String] = ["custom_dismiss_action"]
    ) -> NotificationService.PreparedNotification {
        .init(
            title: "Emergency",
            body: "Alice needs help",
            eventKey: "emergency_alert:abc123",
            deepLinkUri: deepLinkUri,
            osCategoryId: osCategoryId,
            osCategoryOptions: osCategoryOptions
        )
    }

    /// Scenario: core attached `os_category_id`, so the delivered content
    /// carries exactly that identifier without shell-side interpretation.
    func testContentCarriesCoreSuppliedOsCategoryId() {
        let content = NotificationService.notificationContent(for: prepared())

        XCTAssertEqual(content.categoryIdentifier, "emergency_alert")
        XCTAssertEqual(content.title, "Emergency")
        XCTAssertEqual(content.body, "Alice needs help")
    }

    /// Scenario: the tap target core supplied is the only value stashed, so
    /// `deepLinkUri(from:)` recovers it at tap time and no domain field name
    /// leaks into the OS payload.
    func testContentStashesOnlyCoreSuppliedDeepLink() {
        let content = NotificationService.notificationContent(for: prepared(deepLinkUri: "vauchi://contact/bob"))

        XCTAssertEqual(NotificationService.deepLinkUri(from: content.userInfo), "vauchi://contact/bob")
        XCTAssertEqual(content.userInfo.keys.compactMap { $0 as? String }, ["deep_link_uri"])
    }

    /// Scenario: a notification without a tap target stashes nothing, so the
    /// tap handler opens the app without forwarding a spurious URI.
    func testContentWithoutDeepLinkHasEmptyUserInfo() {
        let content = NotificationService.notificationContent(for: prepared(deepLinkUri: nil))

        XCTAssertNil(NotificationService.deepLinkUri(from: content.userInfo))
        XCTAssertTrue(content.userInfo.isEmpty)
    }

    /// Scenario: core's `custom_dismiss_action` token becomes the OS option on
    /// a category keyed by core's id, so dismissals are reported for
    /// emergencies without the shell knowing what an emergency is.
    func testOsCategoryMapsCoreOptionTokens() {
        let category = NotificationService.osCategory(for: prepared())

        XCTAssertEqual(category.identifier, "emergency_alert")
        XCTAssertEqual(category.options, .customDismissAction)
    }

    /// Scenario: a token this shell does not know is dropped rather than
    /// guessed, so a newer core cannot enable an unreviewed OS behaviour.
    func testOsCategoryIgnoresUnknownOptionTokens() {
        let category = NotificationService.osCategory(for: prepared(
            osCategoryId: "contact_added",
            osCategoryOptions: ["not_a_token"]
        ))

        XCTAssertEqual(category.identifier, "contact_added")
        XCTAssertEqual(category.options, [])
    }

    /// Scenario: registering a category core already addressed replaces the
    /// earlier registration, so core's latest options win and other
    /// registered categories survive.
    func testMergedCategoriesReplaceSameIdentifierAndKeepOthers() {
        let stale = UNNotificationCategory(
            identifier: "emergency_alert",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let other = UNNotificationCategory(
            identifier: "contact_added",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let merged = NotificationService.mergedCategories(
            [stale, other],
            adding: NotificationService.osCategory(for: prepared())
        )
        let byId = Dictionary(uniqueKeysWithValues: merged.map { ($0.identifier, $0) })

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(byId["emergency_alert"]?.options, .customDismissAction)
        XCTAssertEqual(byId["contact_added"]?.options, [])
    }
}
