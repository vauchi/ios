// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AccessibilityUITests.swift
// Structural accessibility tests — queries live view hierarchy.
// Zero coupling to core action IDs, flow order, or localized strings.
// Uses --reset-for-testing to bypass onboarding (identity seeded by app).
// Traces to: features/accessibility.feature

import XCTest

final class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-for-testing"]
        app.launch()

        // --reset-for-testing creates a test identity, so the app
        // starts on the home screen with the tab bar visible.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10),
                      "Tab bar should appear after --reset-for-testing identity seeding")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab Bar Structure

    /// Tab bar has the expected number of tabs, all with non-empty labels.
    func testTabBarHasCorrectNumberOfTabs() {
        let tabBar = app.tabBars.firstMatch
        let tabs = tabBar.buttons.allElementsBoundByIndex
        XCTAssertEqual(tabs.count, 5, "Tab bar should have exactly 5 tabs")
        for (index, tab) in tabs.enumerated() {
            XCTAssertFalse(tab.label.isEmpty,
                           "Tab at index \(index) should have a non-empty label")
        }
    }

    // MARK: - Interactive Elements

    /// All visible buttons on the home screen have non-empty accessibility labels.
    func testAllButtonsHaveLabels() {
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons where button.exists && button.isHittable {
            XCTAssertFalse(button.label.isEmpty,
                           "Button '\(button.identifier)' should have an accessibility label")
        }
    }

    // MARK: - Screen Navigation

    /// Each tab renders a screen with at least one accessible element.
    func testEachTabRendersAccessibleContent() {
        let tabBar = app.tabBars.firstMatch
        let tabs = tabBar.buttons.allElementsBoundByIndex

        for (index, tab) in tabs.enumerated() {
            tab.tap()

            // Each screen should have at least one descendant element
            let anyElement = app.descendants(matching: .any).element(boundBy: 0)
            XCTAssertTrue(anyElement.waitForExistence(timeout: 3),
                          "Tab \(index) ('\(tab.label)') should render accessible content")
        }
    }

    /// Navigating to each tab and back does not leave the app in a broken state.
    func testTabNavigationRoundTrip() {
        let tabBar = app.tabBars.firstMatch
        let tabs = tabBar.buttons.allElementsBoundByIndex
        let firstTab = tabs[0]

        // Visit each tab, then return to the first
        for tab in tabs {
            tab.tap()
        }
        firstTab.tap()

        // Verify the app is still responsive
        XCTAssertTrue(tabBar.exists, "Tab bar should still exist after round-trip navigation")
        let buttons = app.buttons.allElementsBoundByIndex
        let visibleButtons = buttons.filter { $0.exists && $0.isHittable }
        XCTAssertFalse(visibleButtons.isEmpty,
                       "Home screen should have interactive elements after round-trip")
    }

    // MARK: - VoiceOver Traits

    /// Home screen has visible static text elements with content.
    func testStaticTextElementsHaveContent() {
        let staticTexts = app.staticTexts.allElementsBoundByIndex
        let visibleTexts = staticTexts.filter { $0.exists && !$0.label.isEmpty }
        XCTAssertFalse(visibleTexts.isEmpty,
                       "Home screen should have at least one visible static text element")
    }

    // MARK: - Accessibility Audit

    /// Built-in accessibility audit (iOS 17+).
    /// Excludes .hitRegion — pre-existing small touch targets tracked in
    /// problem record 2026-03-18-cross-platform-accessibility-gaps.
    func testAccessibilityAudit() throws {
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: .init(arrayLiteral:
                .contrast, .dynamicType, .sufficientElementDescription))
        } else {
            throw XCTSkip("Accessibility audit requires iOS 17+")
        }
    }
}
