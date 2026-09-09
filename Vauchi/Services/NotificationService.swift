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

    /// Relays a tapped notification's Core-supplied deep-link URI to the app,
    /// which forwards it as a generic `DeepLinkOpened` event (the same path as
    /// `.onOpenURL`). The service never interprets the URI; Core owns routing.
    /// Buffers a cold-launch tap until the app wires the handler.
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

    /// Register the OS categories core addresses through `os_category_id`.
    func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(Set(Self.osCategories()))
    }

    /// The `UNNotificationCategory` set keyed by the `os_category_id` values
    /// core emits. Registration precedes any notification, so the id list
    /// is fixed here rather than read off a pending notification's
    /// `os_category_options`.
    /// TODO(HUMBLE): [W, P1] core should publish the category registry
    /// (ids + options) so the shell registers without knowing them
    /// (see _private problem record 2026-07-06-mobile-domain-shell-violations).
    static func osCategories() -> [UNNotificationCategory] {
        [
            UNNotificationCategory(
                identifier: "emergency_alert",
                actions: [],
                intentIdentifiers: [],
                options: .customDismissAction
            ),
            UNNotificationCategory(
                identifier: "contact_added",
                actions: [],
                intentIdentifiers: [],
                options: []
            ),
        ]
    }

    /// Poll for and display OS notifications (legacy path used by the
    /// retired 30-second heartbeat; kept for BackgroundSyncService until
    /// that path migrates to `on_wakeup`).
    func pollAndDisplayNotifications(repository: VauchiRepository?) {
        guard SettingsService.shared.notificationsEnabled else { return }
        guard let notifications = repository?.pollNotifications(), !notifications.isEmpty else { return }

        for notification in notifications {
            showNotification(notification)
        }
    }

    /// Display notifications produced by `PlatformAppEngine.onWakeup()`
    /// (ADR-044 Am2a). Called from `AppViewModel.onWakeup`.
    func displayWakeupNotifications(_ notifications: [WakeupNotification]) {
        guard SettingsService.shared.notificationsEnabled else { return }
        guard !notifications.isEmpty else { return }

        for notification in notifications {
            showWakeupNotification(notification)
        }
    }

    /// Display a single `onWakeup` notification.
    private func showWakeupNotification(_ notification: WakeupNotification) {
        deliver(PreparedNotification(
            title: notification.title,
            body: notification.body,
            contactId: notification.contactId,
            eventKey: notification.eventKey,
            deepLinkUri: notification.deepLinkUri,
            osCategoryId: notification.osCategoryId
        ))
    }

    /// Display a single notification.
    func showNotification(_ notification: MobilePendingNotification) {
        deliver(PreparedNotification(
            title: notification.title,
            body: notification.body,
            contactId: notification.contactId,
            eventKey: notification.eventKey,
            deepLinkUri: notification.deepLinkUri,
            osCategoryId: notification.osCategoryId
        ))
    }

    /// The core-prepared values one OS notification is built from, shared
    /// by the typed (`MobilePendingNotification`) and wakeup-JSON paths.
    struct PreparedNotification {
        let title: String
        let body: String
        let contactId: String
        let eventKey: String
        let deepLinkUri: String?
        let osCategoryId: String
    }

    /// Assemble OS content from core-prepared values. Pure so it is
    /// unit-testable without a live `UNUserNotificationCenter`.
    static func notificationContent(for notification: PreparedNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = notification.osCategoryId
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
        return content
    }

    private func deliver(_ notification: PreparedNotification) {
        let request = UNNotificationRequest(
            identifier: notification.eventKey,
            content: Self.notificationContent(for: notification),
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
