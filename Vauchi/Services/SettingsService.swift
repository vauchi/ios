// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SettingsService.swift
// Persistent settings storage using UserDefaults

import Foundation
import UIKit
import VauchiPlatform

/// Keys for UserDefaults storage
private enum SettingsKey: String {
    case relayUrl = "vauchi.relayUrl"
    case lastSyncTime = "vauchi.lastSyncTime"
    case autoSyncEnabled = "vauchi.autoSyncEnabled"
    case syncOnLaunch = "vauchi.syncOnLaunch"
    case notificationsEnabled = "vauchi.notificationsEnabled"
    case hasCompletedOnboarding = "vauchi.hasCompletedOnboarding"
    case hasDismissedDemoContact = "vauchi.hasDismissedDemoContact"

    // Accessibility settings
    case reduceMotion = "vauchi.accessibility.reduceMotion"
    case highContrast = "vauchi.accessibility.highContrast"
    case largeTouchTargets = "vauchi.accessibility.largeTouchTargets"
}

/// Service for managing persistent app settings
final class SettingsService {
    static let shared = SettingsService()

    private let defaults: UserDefaults

    /// Default relay server URL
    static let defaultRelayUrl = "wss://relay.vauchi.app"

    /// Initialize with default UserDefaults
    private convenience init() {
        self.init(defaults: .standard)
    }

    /// Initialize with custom UserDefaults (for testing)
    init(defaults: UserDefaults) {
        self.defaults = defaults
        registerDefaults()
    }

    /// Register default values
    private func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.relayUrl.rawValue: Self.defaultRelayUrl,
            SettingsKey.autoSyncEnabled.rawValue: true,
            SettingsKey.syncOnLaunch.rawValue: true,
            SettingsKey.notificationsEnabled.rawValue: true,
        ])
    }

    // MARK: - Relay Settings

    /// The WebSocket URL of the relay server
    var relayUrl: String {
        get { defaults.string(forKey: SettingsKey.relayUrl.rawValue) ?? Self.defaultRelayUrl }
        set { defaults.set(newValue, forKey: SettingsKey.relayUrl.rawValue) }
    }

    /// Validates a relay URL.
    /// Delegates to core (ADR-021: core owns all validation logic).
    func isValidRelayUrl(_ url: String) -> Bool {
        VauchiPlatform.isValidRelayUrl(url: url)
    }

    // MARK: - Sync Settings

    /// Last successful sync time
    var lastSyncTime: Date? {
        get { defaults.object(forKey: SettingsKey.lastSyncTime.rawValue) as? Date }
        set { defaults.set(newValue, forKey: SettingsKey.lastSyncTime.rawValue) }
    }

    /// Whether to automatically sync in the background
    var autoSyncEnabled: Bool {
        get { defaults.bool(forKey: SettingsKey.autoSyncEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.autoSyncEnabled.rawValue) }
    }

    /// Whether to sync when the app launches
    var syncOnLaunch: Bool {
        get { defaults.bool(forKey: SettingsKey.syncOnLaunch.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.syncOnLaunch.rawValue) }
    }

    // MARK: - Notification Settings

    /// Whether push notifications are enabled
    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: SettingsKey.notificationsEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.notificationsEnabled.rawValue) }
    }

    // MARK: - Onboarding Settings

    /// Whether the user has completed the onboarding flow
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: SettingsKey.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.hasCompletedOnboarding.rawValue) }
    }

    /// Whether the user has dismissed the demo contact
    var hasDismissedDemoContact: Bool {
        get { defaults.bool(forKey: SettingsKey.hasDismissedDemoContact.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.hasDismissedDemoContact.rawValue) }
    }

    // MARK: - Accessibility Settings

    /// Whether to reduce motion/animations (supplements system setting)
    var reduceMotion: Bool {
        get { defaults.bool(forKey: SettingsKey.reduceMotion.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.reduceMotion.rawValue) }
    }

    /// Whether to use high contrast mode (supplements system setting)
    var highContrast: Bool {
        get { defaults.bool(forKey: SettingsKey.highContrast.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.highContrast.rawValue) }
    }

    /// Whether to use larger touch targets (56pt instead of 44pt minimum)
    var largeTouchTargets: Bool {
        get { defaults.bool(forKey: SettingsKey.largeTouchTargets.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.largeTouchTargets.rawValue) }
    }

    /// Combined check for reduce motion (system or app setting)
    var shouldReduceMotion: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    /// Combined check for high contrast (system or app setting)
    var shouldUseHighContrast: Bool {
        highContrast || UIAccessibility.isDarkerSystemColorsEnabled
    }

    /// Minimum touch target size based on settings
    var minimumTouchTargetSize: CGFloat {
        largeTouchTargets ? 56 : 44
    }

    // MARK: - Reset

    /// Resets all settings to defaults
    func resetToDefaults() {
        for key in [
            SettingsKey.relayUrl,
            SettingsKey.lastSyncTime,
            SettingsKey.autoSyncEnabled,
            SettingsKey.syncOnLaunch,
            SettingsKey.notificationsEnabled,
            SettingsKey.hasCompletedOnboarding,
            SettingsKey.hasDismissedDemoContact,
            SettingsKey.reduceMotion,
            SettingsKey.highContrast,
            SettingsKey.largeTouchTargets,
        ] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Reset onboarding state (for replay from settings)
    func resetOnboarding() {
        defaults.removeObject(forKey: SettingsKey.hasCompletedOnboarding.rawValue)
    }
}
