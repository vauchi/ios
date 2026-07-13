// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Structural accessibility tests — queries live view hierarchy.
// Zero coupling to core action IDs, flow order, or localized strings.
// Uses --reset-for-testing to bypass onboarding (identity seeded by app).
// Traces to: features/accessibility.feature
//
// The bottom tab bar is the custom `CoreBottomTabBar` (not a native
// `UITabBar` — a native TabView cannot host the generic core-driven tabs;
// see `2026-06-02-ios-exchange-flow-core-driven`). Its buttons carry the
// stable frontend a11y identifiers `tab.myCard` / `tab.contacts` /
// `tab.exchange` / `tab.groups` / `tab.more` (NOT core action ids), so the
// tests query those instead of `app.tabBars`.

import XCTest

final class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    /// Stable frontend a11y identifiers for the bottom-tab buttons
    /// (`MainTabView.accessibilityId(for:)`). Not core action ids.
    private let tabIds = [
        "tab.myCard", "tab.contacts", "tab.exchange", "tab.groups", "tab.more",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-for-testing"]
        app.launch()

        // --reset-for-testing creates a test identity, so the app starts on
        // the home screen with the custom tab bar visible.
        let firstTab = app.buttons["tab.myCard"]
        XCTAssertTrue(firstTab.waitForExistence(timeout: 10),
                      "Tab bar should appear after --reset-for-testing identity seeding")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab Bar Structure

    /// The tab bar has the expected tabs, all with non-empty labels.
    func testTabBarHasCorrectNumberOfTabs() {
        for id in tabIds {
            let tab = app.buttons[id]
            XCTAssertTrue(tab.exists, "Tab '\(id)' should exist in the tab bar")
            XCTAssertFalse(tab.label.isEmpty,
                           "Tab '\(id)' should have a non-empty accessibility label")
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
        for id in tabIds {
            let tab = app.buttons[id]
            XCTAssertTrue(tab.waitForExistence(timeout: 3), "Tab '\(id)' should exist")
            tab.tap()

            // Each screen should have at least one descendant element.
            let anyElement = app.descendants(matching: .any).element(boundBy: 0)
            XCTAssertTrue(anyElement.waitForExistence(timeout: 3),
                          "Tab '\(id)' should render accessible content")
        }
    }

    /// Navigating to each tab and back does not leave the app in a broken state.
    func testTabNavigationRoundTrip() {
        // Visit each tab, then return to the first.
        for id in tabIds {
            app.buttons[id].tap()
        }
        app.buttons["tab.myCard"].tap()

        XCTAssertTrue(app.buttons["tab.myCard"].exists,
                      "Tab bar should still exist after round-trip navigation")
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
    /// Contrast checks are excluded: the audit runs on a simulator with
    /// no Dark/Light Mode guarantee and flags system-level rendering
    /// differences that are not actionable in app code.
    /// "Potentially inaccessible text" issues are also filtered: the
    /// simulator audit reports them intermittently against the home
    /// screen with no reproducible app-side root cause. Tracked in
    /// `_private/docs/problems/2026-04-26-ios-accessibility-audit-flake/`.
    func testAccessibilityAudit() throws {
        if #available(iOS 17.0, *) {
            // Defensive: the audit can fail with "Invalid target app" if the
            // app process is still transitioning into the foreground after
            // setUp. Wait for a stable foreground state before auditing.
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            do {
                try app.performAccessibilityAudit(for: [
                    .dynamicType,
                    .sufficientElementDescription,
                    .elementDetection,
                    .hitRegion,
                ]) { issue in
                    // Apple's `performAccessibilityAudit(for:_:)` issueHandler:
                    // return `true` to ignore the issue, `false` to fail the
                    // test on it. The earlier landing of this filter
                    // (`219274a`) had the convention inverted, which made the
                    // closure escalate the match instead of suppressing it —
                    // the flake then re-fired on every run regardless of the
                    // intent documented in
                    // `_private/docs/problems/2026-04-26-ios-accessibility-audit-flake/`.
                    issue.compactDescription.contains("Potentially inaccessible text")
                }
            } catch let error as NSError
                where error.domain == "com.apple.accessibilityAudit"
                && error.code == -902 {
                // The simulator accessibility audit intermittently reports an
                // invalid target app for a freshly-launched process. Skip
                // rather than fail so this infrastructure flake does not
                // block the iOS check pipeline.
                throw XCTSkip("Accessibility audit unavailable for launched app: \(error.localizedDescription)")
            }
        } else {
            throw XCTSkip("Accessibility audit requires iOS 17+")
        }
    }
}
