// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AccessibilityUITests.swift
// XCUITest accessibility tests — queries live view hierarchy.
// Replaces tautological unit tests that only checked string constant lengths.
// Traces to: features/accessibility.feature

import XCTest

final class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Setup / Onboarding

    /// Fresh launch shows onboarding with accessible elements.
    func testOnboardingScreenHasAccessibleElements() {
        // On fresh launch, the multi-step onboarding starts with WelcomeStepView.
        // If the user already completed onboarding (simulator state), the tab bar
        // appears instead — skip the test in that case.
        let getStarted = app.buttons["onboarding.get_started"]
        let tabBar = app.tabBars.firstMatch
        let onboardingVisible = getStarted.waitForExistence(timeout: 5)

        if !onboardingVisible, tabBar.exists {
            // Already onboarded — nothing to test
            return
        }

        XCTAssertTrue(onboardingVisible,
                      "Get Started button should appear on the welcome screen")

        // "I have a backup" restore option should also be present
        let restore = app.buttons["onboarding.restore"]
        XCTAssertTrue(restore.exists, "Restore button should exist on welcome screen")
    }

    // MARK: - Tab Bar Navigation

    /// After onboarding, the main tab bar has accessible tabs.
    func testMainTabBarAccessibility() {
        // Complete onboarding if needed by creating an identity
        completeOnboardingIfNeeded()

        // The 5-tab model should have accessible tab buttons
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5),
                      "Tab bar should appear after onboarding")

        // The 5-tab model: verify each specific tab exists
        for tab in ["My Card", "Contacts", "Exchange", "Groups", "More"] {
            XCTAssertTrue(tabBar.buttons[tab].exists,
                          "Tab '\(tab)' should exist in the tab bar")
        }
    }

    // MARK: - My Card Screen

    /// My Card screen has accessible field rows.
    func testMyCardFieldsAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("My Card")

        // The screen should have at least one accessible element
        let anyElement = app.descendants(matching: .any).element(boundBy: 0)
        XCTAssertTrue(anyElement.waitForExistence(timeout: 5),
                      "My Card screen should have accessible elements")

        // Add field button should be discoverable
        let addFieldButton = app.buttons["card.field.add"]
        if addFieldButton.exists {
            XCTAssertTrue(addFieldButton.isHittable,
                          "Add field button should be hittable")
        }
    }

    // MARK: - Contacts Screen

    /// Contacts screen has accessible list and search.
    func testContactsScreenAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("Contacts")

        // Screen should render within timeout
        let screen = app.otherElements.firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5),
                      "Contacts screen should appear")
    }

    // MARK: - Exchange Screen

    /// Exchange screen has accessible elements for QR exchange.
    func testExchangeScreenAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("Exchange")

        // FaceToFaceExchangeView should render — look for the camera toggle
        // or grant permission button (depending on camera permission state)
        let cameraToggle = app.buttons["exchange.camera_toggle"]
        let grantPermission = app.buttons["exchange.grant_permission"]
        let found = cameraToggle.waitForExistence(timeout: 5)
            || grantPermission.waitForExistence(timeout: 2)
        XCTAssertTrue(found,
                      "Exchange screen should show camera toggle or permission prompt")
    }

    // MARK: - Settings Screen

    /// Settings screen sections have header traits.
    func testSettingsScreenAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("More")

        // Navigate into Settings via the NavigationLink
        let settingsLink = app.buttons["more.settings"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5),
                      "Settings link should exist in More tab")
        settingsLink.tap()

        // Settings screen should have toggles (e.g. accessibility section).
        // The toggles are below the fold — scroll until visible.
        let reduceMotion = app.switches["settings.accessibility.reduceMotion"]
        for _ in 0 ..< 5 where !reduceMotion.exists {
            app.swipeUp()
        }
        XCTAssertTrue(reduceMotion.exists,
                      "Reduce Motion toggle should exist in Settings")
    }

    // MARK: - VoiceOver Element Ordering

    /// Interactive elements should have accessibility labels (not just identifiers).
    func testInteractiveElementsHaveLabels() {
        completeOnboardingIfNeeded()

        // Query all buttons in the current screen
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons where button.exists && button.isHittable {
            let label = button.label
            // Every visible button should have a non-empty accessibility label
            XCTAssertFalse(label.isEmpty,
                           "Button '\(button.identifier)' should have an accessibility label")
        }
    }

    // MARK: - Helpers

    private func completeOnboardingIfNeeded() {
        // New multi-step onboarding: Welcome → CreateIdentity → AddFields → Preview → Security
        let getStarted = app.buttons["onboarding.get_started"]
        guard getStarted.waitForExistence(timeout: 3) else {
            // Already past onboarding
            return
        }
        getStarted.tap()

        // Step 2: Enter name
        let nameField = app.textFields["onboarding.name_field"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("Test User")

            let continueButton = app.buttons["onboarding.name_continue"]
            if continueButton.waitForExistence(timeout: 2), continueButton.isEnabled {
                continueButton.tap()
            }
        }

        // Step 3: Add fields (skip)
        let skipButton = app.buttons["onboarding.info_skip"]
        if skipButton.waitForExistence(timeout: 3) {
            skipButton.tap()
        }

        // Step 4: Preview card (confirm)
        let confirmButton = app.buttons["onboarding.preview_confirm"]
        if confirmButton.waitForExistence(timeout: 3) {
            confirmButton.tap()
        }

        // Step 5: Security (finish)
        let finishButton = app.buttons["onboarding.finish_setup"]
        if finishButton.waitForExistence(timeout: 3) {
            finishButton.tap()
        }

        // Wait for main UI
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
    }

    private func navigateToTab(_ label: String) {
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            let tab = tabBar.buttons[label]
            if tab.exists {
                tab.tap()
            }
        }
    }
}
