// LocalizationService.swift
// Internationalization service using vauchi-mobile bindings

import Combine
import Foundation
import VauchiMobile

/// Keys for locale-related UserDefaults storage
private enum LocaleSettingsKey: String {
    case selectedLocaleCode = "vauchi.locale.selectedCode"
    case followSystem = "vauchi.locale.followSystem"
}

/// Service for managing app localization
final class LocalizationService: ObservableObject {
    static let shared = LocalizationService()

    private let defaults: UserDefaults

    /// Published current locale
    @Published var currentLocale: MobileLocale = .english

    /// Published list of available locales
    @Published var availableLocales: [MobileLocaleInfo] = []

    /// Initialize with default UserDefaults
    private convenience init() {
        self.init(defaults: .standard)
    }

    /// Initialize with custom UserDefaults (for testing)
    init(defaults: UserDefaults) {
        self.defaults = defaults
        registerDefaults()
        loadLocales()
    }

    /// Register default values
    private func registerDefaults() {
        defaults.register(defaults: [
            LocaleSettingsKey.followSystem.rawValue: true,
        ])
    }

    /// Load available locales and set current locale
    private func loadLocales() {
        availableLocales = getAvailableLocales()
        applySelectedLocale()
    }

    // MARK: - Settings

    /// Currently selected locale code
    var selectedLocaleCode: String? {
        get { defaults.string(forKey: LocaleSettingsKey.selectedLocaleCode.rawValue) }
        set {
            defaults.set(newValue, forKey: LocaleSettingsKey.selectedLocaleCode.rawValue)
            applySelectedLocale()
        }
    }

    /// Whether to follow system language
    var followSystem: Bool {
        get { defaults.bool(forKey: LocaleSettingsKey.followSystem.rawValue) }
        set {
            defaults.set(newValue, forKey: LocaleSettingsKey.followSystem.rawValue)
            applySelectedLocale()
        }
    }

    // MARK: - Locale Selection

    /// Apply the currently selected locale
    func applySelectedLocale() {
        if let code = selectedLocaleCode, !followSystem {
            if let locale = parseLocaleCode(code: code) {
                currentLocale = locale
                return
            }
        }

        // Use system language
        let systemLanguage: String
        if #available(iOS 16.0, *) {
            systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            systemLanguage = Locale.current.languageCode ?? "en"
        }
        if let locale = parseLocaleCode(code: systemLanguage) {
            currentLocale = locale
        } else {
            currentLocale = .english
        }
    }

    /// Select a locale by code
    func selectLocale(code: String) {
        followSystem = false
        selectedLocaleCode = code
    }

    /// Select a locale directly
    func selectLocale(_ locale: MobileLocale) {
        let info = getLocaleInfo(locale: locale)
        selectLocale(code: info.code)
    }

    /// Reset to follow system language
    func resetToSystem() {
        followSystem = true
        selectedLocaleCode = nil
        applySelectedLocale()
    }

    // MARK: - String Lookup

    /// Get a localized string by key
    func t(_ key: String) -> String {
        getString(locale: currentLocale, key: key)
    }

    /// Get a localized string with arguments
    func t(_ key: String, args: [String: String]) -> String {
        getStringWithArgs(locale: currentLocale, key: key, args: args)
    }

    // MARK: - Convenience

    /// Get info for the current locale
    var currentLocaleInfo: MobileLocaleInfo {
        getLocaleInfo(locale: currentLocale)
    }

    /// Check if current locale is RTL
    var isRightToLeft: Bool {
        currentLocaleInfo.isRtl
    }
}
