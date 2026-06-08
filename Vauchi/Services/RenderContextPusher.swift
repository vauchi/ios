// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Pushes the union of `ThemeService` + `LocalizationService` state to
// core's `RenderContext` via `setRenderContextJson`. Mirrors macOS's
// `RenderContextPusher.swift` and Android's `RenderContextPusher.kt`.
// S4 of `2026-05-16-settings-storage-by-sensitivity`.

import Foundation
import VauchiPlatform

/// Push the union of [ThemeService] and [LocalizationService] state to
/// core's `RenderContext` via `setRenderContextJson`.
///
/// Each service is OS-native canonical (UserDefaults) for its own
/// slice of state (theme / locale) after S4. Core needs to read those
/// values to render the Settings dropdown's `selected` value and to
/// drive locale-aware string lookup. The push is the single wire
/// across the boundary.
///
/// Because `RenderContext` carries both fields as a unit and a JSON
/// push replaces the whole context, every push includes both
/// effective values. This function reads from both singletons and
/// pushes the union — call it from either service after persisting a
/// change.
func pushRenderContext(engine: PlatformAppEngine?) {
    guard let engine else { return }
    let theme = ThemeService.shared
    let locale = LocalizationService.shared
    let effectiveTheme = theme.followSystem ? nil : theme.selectedThemeId
    let effectiveLocale = locale.followSystem ? nil : locale.selectedLocaleCode
    let json = buildRenderContextJson(themeId: effectiveTheme, locale: effectiveLocale)
    do {
        try engine.setRenderContextJson(json: json)
    } catch {
        NSLog("[RenderContextPusher] Failed: \(type(of: error))")
    }
}

/// Build a minimal JSON object for `RenderContext`. Omits keys whose
/// effective value is `nil` ("follow system" semantic per ADR-047).
func buildRenderContextJson(themeId: String?, locale: String?) -> String {
    var parts: [String] = []
    if let themeId {
        parts.append("\"theme_id\":\(jsonString(themeId))")
    }
    if let locale {
        parts.append("\"locale\":\(jsonString(locale))")
    }
    return "{" + parts.joined(separator: ",") + "}"
}

private func jsonString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}
