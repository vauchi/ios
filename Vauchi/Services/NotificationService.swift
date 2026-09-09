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

            DispatchQueue.main.async {
                completion(granted)
            }
        }
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
            eventKey: notification.eventKey,
            deepLinkUri: notification.deepLinkUri,
            osCategoryId: notification.osCategoryId,
            osCategoryOptions: notification.osCategoryOptions ?? []
        ))
    }

    /// Display a single notification.
    func showNotification(_ notification: MobilePendingNotification) {
        deliver(PreparedNotification(
            title: notification.title,
            body: notification.body,
            eventKey: notification.eventKey,
            deepLinkUri: notification.deepLinkUri,
            osCategoryId: notification.osCategoryId,
            osCategoryOptions: notification.osCategoryOptions
        ))
    }

    /// The core-prepared values one OS notification is built from, shared
    /// by the typed (`MobilePendingNotification`) and wakeup-JSON paths.
    struct PreparedNotification {
        let title: String
        let body: String
        let eventKey: String
        let deepLinkUri: String?
        let osCategoryId: String
        let osCategoryOptions: [String]
    }

    /// Assemble OS content from core-prepared values. Pure so it is
    /// unit-testable without a live `UNUserNotificationCenter`.
    static func notificationContent(for notification: PreparedNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = notification.osCategoryId
        // Core supplies the tap target; it is stashed verbatim so `didReceive`
        // can relay it back as a generic `DeepLinkOpened` event.
        content.userInfo = notification.deepLinkUri.map { ["deep_link_uri": $0] } ?? [:]
        return content
    }

    /// The OS options core's `os_category_options` tokens name. A token this
    /// shell does not know is dropped so a newer core cannot enable an
    /// unreviewed OS behaviour.
    private static let osCategoryOptionsByToken: [String: UNNotificationCategoryOptions] = [
        "custom_dismiss_action": .customDismissAction,
    ]

    /// The `UNNotificationCategory` a core-prepared notification addresses,
    /// built from core's opaque id and option tokens. Pure so it is
    /// unit-testable without a live `UNUserNotificationCenter`.
    static func osCategory(for notification: PreparedNotification) -> UNNotificationCategory {
        let options = notification.osCategoryOptions.reduce(into: UNNotificationCategoryOptions()) { options, token in
            if let option = osCategoryOptionsByToken[token] {
                options.insert(option)
            }
        }
        return UNNotificationCategory(
            identifier: notification.osCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: options
        )
    }

    /// The registered set after `category` joins it, replacing any earlier
    /// registration of the same id so core's latest options win.
    static func mergedCategories(
        _ existing: Set<UNNotificationCategory>,
        adding category: UNNotificationCategory
    ) -> Set<UNNotificationCategory> {
        var merged = existing.filter { $0.identifier != category.identifier }
        merged.insert(category)
        return merged
    }

    private func deliver(_ notification: PreparedNotification) {
        let request = UNNotificationRequest(
            identifier: notification.eventKey,
            content: Self.notificationContent(for: notification),
            trigger: nil // Deliver immediately
        )
        let category = Self.osCategory(for: notification)
        let center = UNUserNotificationCenter.current()

        // The category is registered per delivery because its options only
        // apply to requests added afterwards, and core — not a fixed list
        // here — owns which ids exist.
        center.getNotificationCategories { existing in
            center.setNotificationCategories(Self.mergedCategories(existing, adding: category))
            center.add(request) { error in
                if let error {
                    #if DEBUG
                        print("NotificationService: Failed to add notification: \(error)")
                    #endif
                }
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
