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

    /// Scenario: Onboarding step tracking
    func testOnboardingStepTracking() {
        XCTAssertEqual(settingsService.onboardingStep, 0,
                       "Initial onboarding step should be 0")

        settingsService.onboardingStep = 3
        XCTAssertEqual(settingsService.onboardingStep, 3)

        // Create new service with same defaults
        let newService = SettingsService(defaults: testDefaults)
        XCTAssertEqual(newService.onboardingStep, 3,
                       "Onboarding step should persist")
    }

    /// Scenario: Reset onboarding
    func testResetOnboarding() {
        settingsService.hasCompletedOnboarding = true
        settingsService.onboardingStep = 4

        settingsService.resetOnboarding()

        XCTAssertFalse(settingsService.hasCompletedOnboarding)
        XCTAssertEqual(settingsService.onboardingStep, 0)
    }

    /// Scenario: Demo contact dismissal
    func testDemoContactDismissal() {
        XCTAssertFalse(settingsService.hasDismissedDemoContact,
                       "Demo contact should not be dismissed initially")

        settingsService.hasDismissedDemoContact = true

        XCTAssertTrue(settingsService.hasDismissedDemoContact)
    }

    // MARK: - Onboarding Step Tests

    /// Scenario: OnboardingStep enum has correct values
    func testOnboardingStepValues() {
        XCTAssertEqual(OnboardingStep.welcome.rawValue, 0)
        XCTAssertEqual(OnboardingStep.createIdentity.rawValue, 1)
        XCTAssertEqual(OnboardingStep.addFields.rawValue, 2)
        XCTAssertEqual(OnboardingStep.preview.rawValue, 3)
        XCTAssertEqual(OnboardingStep.security.rawValue, 4)
        XCTAssertEqual(OnboardingStep.ready.rawValue, 5)
    }

    /// Scenario: User-visible step numbers are correct
    func testUserVisibleStepNumbers() {
        XCTAssertNil(OnboardingStep.welcome.userVisibleStepNumber,
                     "Welcome should not show step number")
        XCTAssertEqual(OnboardingStep.createIdentity.userVisibleStepNumber, 1)
        XCTAssertEqual(OnboardingStep.addFields.userVisibleStepNumber, 2)
        XCTAssertEqual(OnboardingStep.preview.userVisibleStepNumber, 3)
        XCTAssertEqual(OnboardingStep.security.userVisibleStepNumber, 4)
        XCTAssertNil(OnboardingStep.ready.userVisibleStepNumber,
                     "Ready should not show step number")
    }

    /// Scenario: Total user-visible steps is 4
    func testTotalUserVisibleSteps() {
        XCTAssertEqual(OnboardingStep.userVisibleStepCount, 4)
    }

    // MARK: - Onboarding Data Tests

    /// Scenario: OnboardingData has minimum data with name only
    func testOnboardingDataMinimumWithName() {
        let data = OnboardingData()
        XCTAssertFalse(data.hasMinimumData, "Empty data should not have minimum")

        data.displayName = "  "
        XCTAssertFalse(data.hasMinimumData, "Whitespace-only name should not count")

        data.displayName = "Alice"
        XCTAssertTrue(data.hasMinimumData, "Name should satisfy minimum requirement")
    }

    /// Scenario: OnboardingData stores all fields
    func testOnboardingDataFields() {
        let data = OnboardingData()
        data.displayName = "Bob"
        data.phone = "+1234567890"
        data.email = "bob@example.com"

        XCTAssertEqual(data.displayName, "Bob")
        XCTAssertEqual(data.phone, "+1234567890")
        XCTAssertEqual(data.email, "bob@example.com")
    }
}
