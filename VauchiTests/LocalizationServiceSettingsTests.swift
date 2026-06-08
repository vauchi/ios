// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Pin the UserDefaults-canonical contract for LocalizationService
// introduced by S4 of `2026-05-16-settings-storage-by-sensitivity`:
// the service no longer consults `appEngine.appPreferences()` for
// reads — the `vauchi.locale.*` UserDefaults keys are the only source
// of truth. The render-context push to core is a separate code path
// tested elsewhere. Mirrors macOS's `LocalizationServiceSettingsTests.swift`
// and Android's `LocalizationManagerSharedPrefsTest.kt`.

@testable import Vauchi
import XCTest

final class LocalizationServiceSettingsTests: XCTestCase {
    // MARK: - Helpers

    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = "vauchi.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Tests

    /// Scenario: defaults follow system when UserDefaults is empty.
    func test_defaults_follow_system_when_user_defaults_empty() {
        let service = LocalizationService(defaults: makeEphemeralDefaults())

        XCTAssertTrue(service.followSystem, "default followSystem is true")
        XCTAssertNil(service.selectedLocaleCode, "default selectedLocaleCode is nil")
    }

    /// Scenario: explicit locale is read from UserDefaults on init.
    func test_reads_explicit_locale_from_user_defaults_on_init() {
        let defaults = makeEphemeralDefaults()
        defaults.set("de", forKey: "vauchi.locale.selectedCode")
        defaults.set(false, forKey: "vauchi.locale.followSystem")

        let service = LocalizationService(defaults: defaults)

        XCTAssertFalse(service.followSystem, "followSystem reflects stored false")
        XCTAssertEqual(
            service.selectedLocaleCode,
            "de",
            "selectedLocaleCode matches stored value"
        )
    }

    /// Scenario: selectLocale persists code and clears followSystem.
    func test_select_locale_persists_code_and_clears_follow_system() {
        let defaults = makeEphemeralDefaults()
        let service = LocalizationService(defaults: defaults)

        service.selectLocale(code: "de")

        XCTAssertEqual(
            defaults.string(forKey: "vauchi.locale.selectedCode"),
            "de",
            "selectedLocaleCode persisted"
        )
        XCTAssertFalse(
            defaults.bool(forKey: "vauchi.locale.followSystem"),
            "followSystem flipped to false"
        )
        XCTAssertFalse(service.followSystem, "service state reflects persisted pick")
        XCTAssertEqual(
            service.selectedLocaleCode,
            "de",
            "service state reflects persisted pick"
        )
    }

    /// Scenario: resetToSystem clears explicit locale and sets followSystem.
    func test_reset_to_system_clears_explicit_locale_and_sets_follow_system() {
        let defaults = makeEphemeralDefaults()
        defaults.set("de", forKey: "vauchi.locale.selectedCode")
        defaults.set(false, forKey: "vauchi.locale.followSystem")
        let service = LocalizationService(defaults: defaults)

        service.resetToSystem()

        XCTAssertTrue(
            defaults.bool(forKey: "vauchi.locale.followSystem"),
            "followSystem restored to true"
        )
        XCTAssertNil(
            defaults.string(forKey: "vauchi.locale.selectedCode"),
            "selectedLocaleCode removed"
        )
        XCTAssertTrue(service.followSystem, "service state reflects reset")
        XCTAssertNil(service.selectedLocaleCode, "service state reflects reset")
    }
}
