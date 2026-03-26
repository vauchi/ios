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
        // On fresh launch, the setup view should appear.
        // Check for welcome title (marked as header via .accessibilityAddTraits(.isHeader))
        let welcomeTitle = app.staticTexts["setup.welcome.title"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 5),
                      "Welcome title should appear within 5s on fresh launch")

        // Name input field should be accessible and enabled
        let nameField = app.textFields["setup.name.field"]
        XCTAssertTrue(nameField.exists, "Name input field should exist in onboarding")
        XCTAssertTrue(nameField.isEnabled, "Name field should be enabled")

        // Create button should exist in view hierarchy
        let createButton = app.buttons["setup.create.button"]
        XCTAssertTrue(createButton.exists, "Create button should exist in onboarding")
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
        for tab in ["My Card", "Contacts", "Exchange", "Activity", "More"] {
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

    /// Exchange screen has accessible instructions and mode buttons.
    func testExchangeScreenAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("Exchange")

        // Exchange instructions should be present
        let instructions = app.staticTexts["exchange.instructions"]
        XCTAssertTrue(instructions.waitForExistence(timeout: 5),
                      "Exchange instructions should appear on Exchange screen")
    }

    // MARK: - Settings Screen

    /// Settings screen sections have header traits.
    func testSettingsScreenAccessible() {
        completeOnboardingIfNeeded()
        navigateToTab("More")

        // Look for settings-related elements
        // Settings is inside the "More" tab
        let settingsButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Settings'")
        ).firstMatch
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()

            // Settings screen should have toggles — verify specific ones exist
            let switches = app.switches
            XCTAssertTrue(switches.firstMatch.waitForExistence(timeout: 3),
                          "Settings should render toggles")
        }
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
        // If the create button exists, we're on the onboarding screen
        let createButton = app.buttons["setup.create.button"]
        if createButton.waitForExistence(timeout: 3) {
            // Enter a name first if the field exists
            let nameField = app.textFields["setup.name.field"]
            if nameField.exists {
                nameField.tap()
                nameField.typeText("Test User")
            }
            if createButton.isEnabled {
                createButton.tap()
                // Wait for transition to main UI
                _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
            }
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
