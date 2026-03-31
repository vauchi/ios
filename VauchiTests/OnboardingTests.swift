// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// OnboardingTests.swift
// Tests for onboarding flow
// Based on: features/onboarding.feature

@testable import Vauchi
import XCTest

final class OnboardingTests: XCTestCase {
    var settingsService: SettingsService!
    var testDefaults: UserDefaults!

    override func setUpWithError() throws {
        // Use a separate UserDefaults for testing
        testDefaults = UserDefaults(suiteName: "test_onboarding")!
        testDefaults.removePersistentDomain(forName: "test_onboarding")
        settingsService = SettingsService(defaults: testDefaults)
    }

    override func tearDownWithError() throws {
        testDefaults.removePersistentDomain(forName: "test_onboarding")
        testDefaults = nil
        settingsService = nil
    }

    // MARK: - Settings Service Tests

    /// Scenario: First launch - onboarding not completed
    func testOnboardingNotCompletedOnFirstLaunch() {
        XCTAssertFalse(settingsService.hasCompletedOnboarding,
                       "Onboarding should not be marked complete on first launch")
    }

    /// Scenario: Mark onboarding as complete
    func testMarkOnboardingComplete() {
        settingsService.hasCompletedOnboarding = true

        XCTAssertTrue(settingsService.hasCompletedOnboarding)
    }

    /// Scenario: Onboarding state persists
    func testOnboardingStatePersists() {
        settingsService.hasCompletedOnboarding = true

        // Create new service with same defaults
        let newService = SettingsService(defaults: testDefaults)
        XCTAssertTrue(newService.hasCompletedOnboarding,
                      "Onboarding completion state should persist")
    }

    /// Scenario: Reset onboarding
    func testResetOnboarding() {
        settingsService.hasCompletedOnboarding = true

        settingsService.resetOnboarding()

        XCTAssertFalse(settingsService.hasCompletedOnboarding)
    }

    /// Scenario: Demo contact dismissal
    func testDemoContactDismissal() {
        XCTAssertFalse(settingsService.hasDismissedDemoContact,
                       "Demo contact should not be dismissed initially")

        settingsService.hasDismissedDemoContact = true

        XCTAssertTrue(settingsService.hasDismissedDemoContact)
    }

    // Onboarding step/data tests removed — custom OnboardingStep enum and
    // OnboardingData class replaced by core-driven MobileOnboardingWorkflow.
    // Core's onboarding state machine is tested in vauchi-core.
}
