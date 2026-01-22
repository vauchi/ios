// SettingsService.swift
// Persistent settings storage using UserDefaults

import Foundation

/// Keys for UserDefaults storage
private enum SettingsKey: String {
    case relayUrl = "vauchi.relayUrl"
    case lastSyncTime = "vauchi.lastSyncTime"
    case autoSyncEnabled = "vauchi.autoSyncEnabled"
    case syncOnLaunch = "vauchi.syncOnLaunch"
    case notificationsEnabled = "vauchi.notificationsEnabled"
    case hasCompletedOnboarding = "vauchi.hasCompletedOnboarding"
    case onboardingStep = "vauchi.onboardingStep"
    case hasDismissedDemoContact = "vauchi.hasDismissedDemoContact"
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
            SettingsKey.notificationsEnabled.rawValue: true
        ])
    }

    // MARK: - Relay Settings

    /// The WebSocket URL of the relay server
    var relayUrl: String {
        get { defaults.string(forKey: SettingsKey.relayUrl.rawValue) ?? Self.defaultRelayUrl }
        set { defaults.set(newValue, forKey: SettingsKey.relayUrl.rawValue) }
    }

    /// Validates a relay URL
    /// Only secure WebSocket (wss://) is allowed in production
    func isValidRelayUrl(_ url: String) -> Bool {
        guard let urlObj = URL(string: url) else { return false }
        let scheme = urlObj.scheme?.lowercased()
        // Security: Only allow secure WebSocket connections
        // ws:// is blocked to prevent MITM attacks
        return scheme == "wss"
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

    /// Current onboarding step (for resume functionality)
    /// 0 = welcome, 1 = identity, 2 = card wizard, 3 = preview, 4 = security, 5 = complete
    var onboardingStep: Int {
        get { defaults.integer(forKey: SettingsKey.onboardingStep.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.onboardingStep.rawValue) }
    }

    /// Whether the user has dismissed the demo contact
    var hasDismissedDemoContact: Bool {
        get { defaults.bool(forKey: SettingsKey.hasDismissedDemoContact.rawValue) }
        set { defaults.set(newValue, forKey: SettingsKey.hasDismissedDemoContact.rawValue) }
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
            SettingsKey.onboardingStep,
            SettingsKey.hasDismissedDemoContact
        ] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Reset onboarding state (for replay from settings)
    func resetOnboarding() {
        defaults.removeObject(forKey: SettingsKey.hasCompletedOnboarding.rawValue)
        defaults.removeObject(forKey: SettingsKey.onboardingStep.rawValue)
    }
}
