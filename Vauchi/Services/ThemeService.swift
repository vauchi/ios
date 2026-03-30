// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ThemeService.swift
// Theme management using vauchi-platform bindings

import Combine
import SwiftUI
import UIKit
import VauchiPlatform

/// Keys for theme-related UserDefaults storage
private enum ThemeSettingsKey: String {
    case selectedThemeId = "vauchi.theme.selectedId"
    case followSystem = "vauchi.theme.followSystem"
}

/// Service for managing app theming
final class ThemeService: ObservableObject {
    static let shared = ThemeService()

    private let defaults: UserDefaults

    /// Published current theme (triggers UI updates)
    @Published var currentTheme: MobileTheme?

    /// Published list of available themes
    @Published var availableThemes: [MobileTheme] = []

    /// Initialize with default UserDefaults
    private convenience init() {
        self.init(defaults: .standard)
    }

    /// Initialize with custom UserDefaults (for testing)
    init(defaults: UserDefaults) {
        self.defaults = defaults
        registerDefaults()
        loadThemes()
    }

    /// Register default values
    private func registerDefaults() {
        defaults.register(defaults: [
            ThemeSettingsKey.followSystem.rawValue: true,
        ])
    }

    /// Load available themes and set current theme
    private func loadThemes() {
        availableThemes = getAvailableThemes()
        applySelectedTheme()
    }

    // MARK: - Settings

    /// Currently selected theme ID
    var selectedThemeId: String? {
        get { defaults.string(forKey: ThemeSettingsKey.selectedThemeId.rawValue) }
        set {
            defaults.set(newValue, forKey: ThemeSettingsKey.selectedThemeId.rawValue)
            applySelectedTheme()
        }
    }

    /// Whether to follow system appearance
    var followSystem: Bool {
        get { defaults.bool(forKey: ThemeSettingsKey.followSystem.rawValue) }
        set {
            defaults.set(newValue, forKey: ThemeSettingsKey.followSystem.rawValue)
            applySelectedTheme()
        }
    }

    // MARK: - Theme Selection

    /// Apply the currently selected theme
    func applySelectedTheme() {
        if let themeId = selectedThemeId, !followSystem {
            currentTheme = getTheme(themeId: themeId)
        } else {
            // Use system preference
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            let defaultId = getDefaultThemeId(preferDark: isDark)
            currentTheme = getTheme(themeId: defaultId)
        }
    }

    /// Select a theme by ID
    func selectTheme(_ themeId: String) {
        followSystem = false
        selectedThemeId = themeId
    }

    /// Reset to follow system appearance
    func resetToSystem() {
        followSystem = true
        selectedThemeId = nil
        applySelectedTheme()
    }

    // MARK: - Color Conversion

    /// Convert hex color string to SwiftUI Color
    func color(from hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }

        guard hexSanitized.count == 6 else {
            return .clear
        }

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    /// Get background primary color
    var bgPrimary: Color {
        guard let theme = currentTheme else { return Color(.systemBackground) }
        return color(from: theme.colors.bgPrimary)
    }

    /// Get background secondary color
    var bgSecondary: Color {
        guard let theme = currentTheme else { return Color(.secondarySystemBackground) }
        return color(from: theme.colors.bgSecondary)
    }

    /// Get primary text color
    var textPrimary: Color {
        guard let theme = currentTheme else { return Color(.label) }
        return color(from: theme.colors.textPrimary)
    }

    /// Get secondary text color
    /// Fallback uses #757575 (4.61:1 on white) instead of secondaryLabel
    /// (3.44:1) to meet WCAG AA 4.5:1 for small text.
    var textSecondary: Color {
        guard let theme = currentTheme else { return color(from: "#757575") }
        return color(from: theme.colors.textSecondary)
    }

    /// Get accent color
    var accent: Color {
        guard let theme = currentTheme else { return .accentColor }
        return color(from: theme.colors.accent)
    }

    /// Get success color
    var success: Color {
        guard let theme = currentTheme else { return .green }
        return color(from: theme.colors.success)
    }

    /// Get error color
    var error: Color {
        guard let theme = currentTheme else { return .red }
        return color(from: theme.colors.error)
    }

    /// Get warning color
    var warning: Color {
        guard let theme = currentTheme else { return .orange }
        return color(from: theme.colors.warning)
    }

    /// Get border color
    var border: Color {
        guard let theme = currentTheme else { return Color(.separator) }
        return color(from: theme.colors.border)
    }

    // MARK: - Grouped Themes

    /// Get dark themes
    var darkThemes: [MobileTheme] {
        availableThemes.filter { $0.mode == .dark }
    }

    /// Get light themes
    var lightThemes: [MobileTheme] {
        availableThemes.filter { $0.mode == .light }
    }
}
