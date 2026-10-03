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

    var authorizer: NotificationAuthorizing = SystemNotificationAuthorizer()

    /// What the OS authorization status allows for a notification about to
    /// be shown (vauchi/private#278).
    enum AuthorizationStep: Equatable {
        case deliver
        case requestFirst
        case drop
    }

    static func authorizationStep(for status: UNAuthorizationStatus) -> AuthorizationStep {
        switch status {
        case .authorized, .provisional, .ephemeral: .deliver
        case .notDetermined: .requestFirst
        case .denied: .drop
        @unknown default: .drop
        }
    }

    /// Asks for permission at the moment a notification is about to be shown,
    /// when the user can see why, rather than at launch; drops it silently if
    /// the user has not allowed notifications (vauchi/private#278).
    static func deliverIfAuthorized(
        _ notification: PreparedNotification,
        authorizer: NotificationAuthorizing,
        deliver: @escaping (PreparedNotification) -> Void
    ) {
        authorizer.currentStatus { status in
            switch authorizationStep(for: status) {
            case .deliver:
                deliver(notification)
            case .requestFirst:
                authorizer.requestAuthorization { granted in
                    if granted {
                        deliver(notification)
                    }
                }
            case .drop:
                break
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
        deliverIfAuthorized(PreparedNotification(
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
        deliverIfAuthorized(PreparedNotification(
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

    private func deliverIfAuthorized(_ notification: PreparedNotification) {
        Self.deliverIfAuthorized(notification, authorizer: authorizer) { [weak self] in
            self?.deliver($0)
        }
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

/// The OS authorization calls `NotificationService` needs, behind a seam
/// because unit tests cannot drive `UNUserNotificationCenter`.
protocol NotificationAuthorizing {
    func currentStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)
}

struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func currentStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if error != nil {
                NSLog("[Vauchi] NotificationService Failed: requestAuthorization")
            }
            completion(granted)
        }
    }
}
