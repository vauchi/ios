// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ThemeSettingsView.swift
// Theme selection view

import SwiftUI
import VauchiMobile

struct ThemeSettingsView: View {
    @ObservedObject private var themeService = ThemeService.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        List {
            // System theme section
            Section {
                Toggle(isOn: Binding(
                    get: { themeService.followSystem },
                    set: { newValue in
                        if newValue {
                            themeService.resetToSystem()
                        } else {
                            themeService.followSystem = false
                        }
                    }
                )) {
                    Label("Follow System", systemImage: "gear")
                }
                .accessibilityIdentifier("theme.followSystem")
            } footer: {
                Text("When enabled, the app will match your device's appearance setting.")
            }

            // Dark themes section
            if !themeService.followSystem {
                Section("Dark Themes") {
                    ForEach(themeService.darkThemes, id: \.id) { theme in
                        ThemeRow(
                            theme: theme,
                            isSelected: themeService.selectedThemeId == theme.id,
                            onSelect: { themeService.selectTheme(theme.id) }
                        )
                    }
                }

                // Light themes section
                Section("Light Themes") {
                    ForEach(themeService.lightThemes, id: \.id) { theme in
                        ThemeRow(
                            theme: theme,
                            isSelected: themeService.selectedThemeId == theme.id,
                            onSelect: { themeService.selectTheme(theme.id) }
                        )
                    }
                }
            }

            // Current theme preview
            if let theme = themeService.currentTheme {
                Section("Preview") {
                    ThemePreviewCard(theme: theme)
                }
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Row displaying a theme option
struct ThemeRow: View {
    let theme: MobileTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Color swatch
                HStack(spacing: 2) {
                    ColorSwatch(hex: theme.colors.bgPrimary)
                    ColorSwatch(hex: theme.colors.accent)
                    ColorSwatch(hex: theme.colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .foregroundColor(.primary)

                    if let author = theme.author {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 8)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .accessibilityIdentifier("theme.select.\(theme.id)")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this theme")
    }
}

/// Small color swatch for theme preview
struct ColorSwatch: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ThemeService.shared.color(from: hex))
            .frame(width: 20, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
    }
}

/// Preview card showing theme colors
struct ThemePreviewCard: View {
    let theme: MobileTheme

    private var themeService: ThemeService {
        ThemeService.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(theme.name)
                    .font(.headline)
                    .foregroundColor(themeService.color(from: theme.colors.textPrimary))
                Spacer()
                Text(theme.mode == .dark ? "Dark" : "Light")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeService.color(from: theme.colors.bgSecondary))
                    .cornerRadius(4)
                    .foregroundColor(themeService.color(from: theme.colors.textSecondary))
            }

            // Sample content
            Text("Sample text with primary color")
                .foregroundColor(themeService.color(from: theme.colors.textPrimary))

            Text("Secondary text color")
                .font(.caption)
                .foregroundColor(themeService.color(from: theme.colors.textSecondary))

            // Color palette
            HStack(spacing: 8) {
                ColorPill(label: "Accent", hex: theme.colors.accent)
                ColorPill(label: "Success", hex: theme.colors.success)
                ColorPill(label: "Error", hex: theme.colors.error)
                ColorPill(label: "Warning", hex: theme.colors.warning)
            }
        }
        .padding()
        .background(themeService.color(from: theme.colors.bgPrimary))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeService.color(from: theme.colors.border), lineWidth: 1)
        )
    }
}

/// Small pill showing a color
struct ColorPill: View {
    let label: String
    let hex: String

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(ThemeService.shared.color(from: hex))
                .frame(width: 24, height: 24)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationView {
        ThemeSettingsView()
    }
}
