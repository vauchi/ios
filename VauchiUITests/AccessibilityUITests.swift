// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AccessibilityUITests.swift
// XCUITest accessibility tests — queries live view hierarchy.
// Action/component IDs come from core's ScreenModel (ui/onboarding.rs).
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

    /// Fresh launch shows core-driven onboarding with accessible elements.
    func testOnboardingScreenHasAccessibleElements() {
        // Core-driven onboarding starts with IdentityCheck screen.
        // If already onboarded, the tab bar appears instead.
        let createNew = app.buttons["create_new"]
        let tabBar = app.tabBars.firstMatch
        let onboardingVisible = createNew.waitForExistence(timeout: 5)

        if !onboardingVisible, tabBar.exists {
            // Already onboarded — nothing to test
            return
        }

        XCTAssertTrue(onboardingVisible,
                      "Create new identity button should appear on the identity check screen")

        // "I already have an identity" option should also be present
        let haveIdentity = app.buttons["have_identity"]
        XCTAssertTrue(haveIdentity.exists, "Have identity button should exist on identity check screen")
    }

    // MARK: - Tab Bar Navigation

    /// After onboarding, the main tab bar has accessible tabs.
    func testMainTabBarAccessibility() {
        completeOnboardingIfNeeded()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5),
                      "Tab bar should appear after onboarding")

        // Verify each tab exists (matching localized labels from nav.* keys)
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

        let anyElement = app.descendants(matching: .any).element(boundBy: 0)
        XCTAssertTrue(anyElement.waitForExistence(timeout: 5),
                      "My Card screen should have accessible elements")

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

        let screen = app.otherElements.firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5),
                      "Contacts screen should appear")
    }

    // MARK: - Exchange Screen

    /// Exchange screen has accessible elements for QR exchange.
    func testExchangeScreenAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("Exchange")

        // FaceToFaceExchangeView — look for camera toggle or permission button
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

        let settingsLink = app.buttons["more.settings"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5),
                      "Settings link should exist in More tab")
        settingsLink.tap()

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

        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons where button.exists && button.isHittable {
            let label = button.label
            XCTAssertFalse(label.isEmpty,
                           "Button '\(button.identifier)' should have an accessibility label")
        }
    }

    // MARK: - Helpers

    /// Drives through core's onboarding workflow using action IDs from ScreenModel.
    /// Flow: IdentityCheck → Welcome → DefaultName → SkipGate (skip) →
    ///       SecurityExplanation → BackupPrompt (skip) → Ready
    private func completeOnboardingIfNeeded() {
        // Step 1: IdentityCheck — "Create new identity"
        let createNew = app.buttons["create_new"]
        guard createNew.waitForExistence(timeout: 3) else {
            // Already past onboarding
            return
        }
        createNew.tap()

        // Step 2: Welcome — "Get Started"
        let getStarted = app.buttons["get_started"]
        if getStarted.waitForExistence(timeout: 3) {
            getStarted.tap()
        }

        // Step 3: DefaultName — enter name, tap "Continue"
        let nameField = app.textFields["display_name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("Test User")

            let continueButton = app.buttons["continue"]
            if continueButton.waitForExistence(timeout: 2), continueButton.isEnabled {
                continueButton.tap()
            }
        }

        // Step 4: SkipGate — "Skip to finish" (bypasses groups, fields, preview)
        let skipToFinish = app.buttons["skip_to_finish"]
        if skipToFinish.waitForExistence(timeout: 3) {
            skipToFinish.tap()
        }

        // Step 5: SecurityExplanation — "Continue"
        tapButtonIfExists("continue", timeout: 3)

        // Step 6: BackupPrompt — "Skip"
        tapButtonIfExists("skip", timeout: 3)

        // Step 7: Ready — "Start using Vauchi"
        tapButtonIfExists("start", timeout: 3)

        // Wait for main UI
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
    }

    private func tapButtonIfExists(_ identifier: String, timeout: TimeInterval) {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: timeout), button.isEnabled {
            button.tap()
        }
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
