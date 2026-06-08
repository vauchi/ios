// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Pin the UserDefaults-canonical contract for ThemeService introduced
// by S4 of `2026-05-16-settings-storage-by-sensitivity`: the service
// no longer consults `appEngine.appPreferences()` for reads — the
// `vauchi.theme.*` UserDefaults keys are the only source of truth.
// The render-context push to core is a separate code path tested
// elsewhere (smoke / integration). Mirrors macOS's
// `ThemeServiceSettingsTests.swift` and Android's
// `ThemeManagerSharedPrefsTest.kt`.

@testable import Vauchi
import XCTest

final class ThemeServiceSettingsTests: XCTestCase {
    // MARK: - Helpers

    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = "vauchi.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Tests

    /// Scenario: defaults follow system when UserDefaults is empty.
    func test_defaults_follow_system_when_user_defaults_empty() {
        let service = ThemeService(defaults: makeEphemeralDefaults())

        XCTAssertTrue(service.followSystem, "default followSystem is true")
        XCTAssertNil(service.selectedThemeId, "default selectedThemeId is nil")
    }

    /// Scenario: explicit theme is read from UserDefaults on init.
    func test_reads_explicit_theme_from_user_defaults_on_init() {
        let defaults = makeEphemeralDefaults()
        defaults.set("cyber", forKey: "vauchi.theme.selectedId")
        defaults.set(false, forKey: "vauchi.theme.followSystem")

        let service = ThemeService(defaults: defaults)

        XCTAssertFalse(service.followSystem, "followSystem reflects stored false")
        XCTAssertEqual(
            service.selectedThemeId,
            "cyber",
            "selectedThemeId matches stored value"
        )
    }

    /// Scenario: selectTheme persists themeId and clears followSystem.
    func test_select_theme_persists_theme_id_and_clears_follow_system() {
        let defaults = makeEphemeralDefaults()
        let service = ThemeService(defaults: defaults)

        service.selectTheme("cyber")

        XCTAssertEqual(
            defaults.string(forKey: "vauchi.theme.selectedId"),
            "cyber",
            "selectedThemeId persisted"
        )
        XCTAssertFalse(
            defaults.bool(forKey: "vauchi.theme.followSystem"),
            "followSystem flipped to false"
        )
        XCTAssertFalse(service.followSystem, "service state reflects persisted pick")
        XCTAssertEqual(
            service.selectedThemeId,
            "cyber",
            "service state reflects persisted pick"
        )
    }

    /// Scenario: resetToSystem clears explicit theme and sets followSystem.
    func test_reset_to_system_clears_explicit_theme_and_sets_follow_system() {
        let defaults = makeEphemeralDefaults()
        defaults.set("cyber", forKey: "vauchi.theme.selectedId")
        defaults.set(false, forKey: "vauchi.theme.followSystem")
        let service = ThemeService(defaults: defaults)

        service.resetToSystem()

        XCTAssertTrue(
            defaults.bool(forKey: "vauchi.theme.followSystem"),
            "followSystem restored to true"
        )
        XCTAssertNil(
            defaults.string(forKey: "vauchi.theme.selectedId"),
            "selectedThemeId removed"
        )
        XCTAssertTrue(service.followSystem, "service state reflects reset")
        XCTAssertNil(service.selectedThemeId, "service state reflects reset")
    }
}
