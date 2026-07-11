// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import UserNotifications
import VauchiPlatform

/// Service for managing local OS notifications on iOS and macOS.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Relays a tapped notification's core-supplied deep-link URI to the app,
    /// which forwards it to core as `UserAction::LinkOpened` (same path as
    /// `.onOpenURL`). Humble: the service never interprets the URI — core owns
    /// routing. Buffers a cold-launch tap until the app wires the handler.
    var onDeepLinkTapped: ((String) -> Void)? {
        didSet {
            guard let uri = pendingDeepLinkUri, let handler = onDeepLinkTapped else { return }
            pendingDeepLinkUri = nil
            handler(uri)
        }
    }

    private var pendingDeepLinkUri: String?

    /// Extracts the deep-link URI stashed in `userInfo` at display time. Pure so
    /// it is unit-testable without a live `UNUserNotificationCenter`.
    static func deepLinkUri(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["deep_link_uri"] as? String
    }

    /// Request notification permissions from the user.
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                #if DEBUG
                    print("NotificationService: requestAuthorization failed: \(error)")
                #endif
            }

            if granted {
                self.registerCategories()
            }

            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// Register notification categories and actions.
    func registerCategories() {
        let center = UNUserNotificationCenter.current()

        // Category for emergency alerts (can have custom actions in future)
        // TODO(HUMBLE): [W, P1] frontend hardcodes OS category identifiers tied to domain notification categories;
        // core should supply `os_category_id` and `os_user_info`
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        let emergencyCategory = UNNotificationCategory(
            identifier: "emergencyAlert",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Category for contact updates
        let updateCategory = UNNotificationCategory(
            identifier: "contactAdded",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([emergencyCategory, updateCategory])
    }

    /// Poll for and display OS notifications (E).
    func pollAndDisplayNotifications(repository: VauchiRepository?) {
        guard SettingsService.shared.notificationsEnabled else { return }
        guard let notifications = repository?.pollNotifications(), !notifications.isEmpty else { return }

        for notification in notifications {
            showNotification(notification)
        }
    }

    /// Display a single notification.
    func showNotification(_ notification: MobilePendingNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // TODO(HUMBLE): [T, P1] frontend assembles notification userInfo from domain field names;
        // core should supply an opaque `os_user_info` map
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        var userInfo: [String: Any] = [
            "contact_id": notification.contactId,
            "event_key": notification.eventKey,
        ]
        // Core supplies the tap target (`vauchi://contact/<id>`); stash it so
        // `didReceive` can relay it back to core as `LinkOpened`.
        if let deepLinkUri = notification.deepLinkUri {
            userInfo["deep_link_uri"] = deepLinkUri
        }
        content.userInfo = userInfo

        // TODO(HUMBLE): [T, P1] frontend maps NotificationCategory to OS presentation ids/sounds;
        // core should attach `os_category_id` and presentation hints
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        switch notification.category {
        case .emergencyAlert:
            content.categoryIdentifier = "emergencyAlert"
            content.sound = .default
        case .duressAlert:
            content.categoryIdentifier = "duressAlert"
            content.sound = .default
        case .contactAdded:
            content.categoryIdentifier = "contactAdded"
        case .cardUpdate:
            content.categoryIdentifier = "cardUpdate"
        }

        let request = UNNotificationRequest(
            identifier: notification.eventKey,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                #if DEBUG
                    print("NotificationService: Failed to add notification: \(error)")
                #endif
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let uri = Self.deepLinkUri(from: response.notification.request.content.userInfo) {
            if let handler = onDeepLinkTapped {
                handler(uri)
            } else {
                pendingDeepLinkUri = uri // cold launch: flush once the app wires the handler
            }
        }

        completionHandler()
    }
}
