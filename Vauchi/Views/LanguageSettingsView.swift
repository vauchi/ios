// LanguageSettingsView.swift
// Language selection view

import SwiftUI

struct LanguageSettingsView: View {
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        List {
            // System language section
            Section {
                Toggle(isOn: Binding(
                    get: { localizationService.followSystem },
                    set: { newValue in
                        if newValue {
                            localizationService.resetToSystem()
                        } else {
                            localizationService.followSystem = false
                        }
                    }
                )) {
                    Label("Follow System", systemImage: "gear")
                }
                .accessibilityIdentifier("language.followSystem")
            } footer: {
                Text("When enabled, the app will use your device's language setting.")
            }

            // Language selection
            if !localizationService.followSystem {
                Section("Available Languages") {
                    ForEach(localizationService.availableLocales, id: \.code) { locale in
                        LanguageRow(
                            locale: locale,
                            isSelected: localizationService.currentLocaleInfo.code == locale.code,
                            onSelect: { localizationService.selectLocale(code: locale.code) }
                        )
                    }
                }
            }

            // Current language info
            Section("Current Language") {
                HStack {
                    Text("Language")
                    Spacer()
                    Text(localizationService.currentLocaleInfo.name)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Code")
                    Spacer()
                    Text(localizationService.currentLocaleInfo.code.uppercased())
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if localizationService.isRightToLeft {
                    HStack {
                        Text("Direction")
                        Spacer()
                        Text("Right to Left")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(localizationService.t("settings.language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Row displaying a language option
struct LanguageRow: View {
    let locale: MobileLocaleInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(locale.name)
                        .foregroundColor(.primary)

                    Text(locale.englishName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(locale.code.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .accessibilityIdentifier("language.select.\(locale.code)")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this language")
    }
}

#Preview {
    NavigationView {
        LanguageSettingsView()
    }
}
