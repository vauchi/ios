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
        content.userInfo = [
            "contact_id": notification.contactId,
            "event_key": notification.eventKey,
        ]

        switch notification.category {
        case .emergencyAlert:
            content.categoryIdentifier = "emergencyAlert"
            content.sound = .default
        case .contactAdded:
            content.categoryIdentifier = "contactAdded"
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
        let userInfo = response.notification.request.content.userInfo
        let contactId = userInfo["contact_id"] as? String

        #if DEBUG
            print("NotificationService: User tapped notification for contact: \(contactId ?? "nil")")
        #endif

        // TODO: Signal app to navigate to contact detail
        // For now, it just opens the app

        completionHandler()
    }
}
