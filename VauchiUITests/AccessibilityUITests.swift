// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Structural accessibility tests — queries live view hierarchy.
// Zero coupling to core action IDs, flow order, or localized strings.
// Uses --reset-for-testing to bypass onboarding (identity seeded by app).
// Traces to: features/accessibility.feature
//
// The presentation-commands migration replaced the custom bottom tab bar
// with core-driven surfaces plus a floating contextual command bar
// (`ContextCommandBarView`). Navigation between sections now goes through
// the bar's navigation command, which opens an overlay listing the
// destinations (`PresentationOverlayView`). The tests query the stable
// frontend a11y identifiers `command.navigation` and
// `navigationDestinations` (NOT core action ids or localized labels).

import XCTest

final class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-for-testing"]
        app.launch()

        // --reset-for-testing creates a test identity, so the app starts on
        // the home surface with the contextual command bar visible.
        let navigationCommand = app.buttons["command.navigation"]
        XCTAssertTrue(navigationCommand.waitForExistence(timeout: 10),
                      "Command bar should appear after --reset-for-testing identity seeding")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private var navigationDestinations: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "navigationDestinations")
            .firstMatch
    }

    /// Waits for `element` to satisfy `predicate`, polling the live
    /// hierarchy rather than sleeping (CC-06).
    private func wait(
        _ element: XCUIElement,
        until predicate: NSPredicate,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Returns the navigation overlay's destination container, opening the
    /// overlay via the command bar unless it is already open.
    ///
    /// The overlay's dismissal animates (`PresentationHostView` runs a 0.24s
    /// ease-out), and an `exists` sample taken during it reports the overlay
    /// still open — so the reopen tap is skipped and the destination list is
    /// read as it disappears. Wait out any dismissal in flight before
    /// deciding.
    @discardableResult
    private func openNavigationDestinations() -> XCUIElement {
        let destinations = navigationDestinations
        _ = wait(destinations, until: NSPredicate(format: "exists == false"), timeout: 2)
        if !destinations.exists {
            let navigationCommand = app.buttons["command.navigation"]
            XCTAssertTrue(navigationCommand.waitForExistence(timeout: 3),
                          "Navigation command should exist on every main destination")
            navigationCommand.tap()
        }
        XCTAssertTrue(destinations.waitForExistence(timeout: 3),
                      "Navigation overlay should list destinations")
        return destinations
    }

    /// Opens the overlay and taps the destination at `index`, returning its
    /// label.
    ///
    /// Taps a coordinate rather than calling `XCUIElement.tap()`. The element
    /// tap path checks hittability first and, when that is not satisfied,
    /// synthesizes a scroll-to-visible drag — which is what killed job
    /// 15799437410: the overlay panel does not scroll, so the drag reached
    /// the dismiss scrim and took the menu down mid-tap. A coordinate tap
    /// delivers the touch at the element's centre and never scrolls.
    ///
    /// Two settle signals were tried here and both were wrong, so neither is
    /// coming back without evidence. `isHittable` reports false for
    /// destinations that tap fine, because the host `ZStack`'s
    /// `contentShape` absorbs the hit test (job 15799571433). Waiting for a
    /// fixed destination count assumed the menu is identical on every
    /// surface, and it is not (job 15799681642).
    @discardableResult
    private func tapDestination(at index: Int) -> String {
        let destinations = openNavigationDestinations().buttons.allElementsBoundByIndex
        XCTAssertTrue(index < destinations.count,
                      "Destination \(index) should be listed "
                          + "(overlay lists \(destinations.count))")
        let destination = destinations[index]
        let label = destination.label
        destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return label
    }

    // MARK: - Navigation Structure

    /// The navigation overlay lists the main destinations, all with
    /// non-empty labels.
    func testNavigationOverlayListsDestinations() {
        let destinations = openNavigationDestinations().buttons
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(destinations.count, 5,
                                    "Navigation overlay should list the main destinations")
        for destination in destinations {
            XCTAssertFalse(destination.label.isEmpty,
                           "Navigation destination should have a non-empty accessibility label")
        }
    }

    // MARK: - Interactive Elements

    /// All visible buttons on the home surface have non-empty accessibility labels.
    func testAllButtonsHaveLabels() {
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons where button.exists && button.isHittable {
            XCTAssertFalse(button.label.isEmpty,
                           "Button '\(button.identifier)' should have an accessibility label")
        }
    }

    // MARK: - Screen Navigation

    /// Each navigation destination renders a surface with at least one
    /// accessible element.
    func testEachDestinationRendersAccessibleContent() {
        let count = openNavigationDestinations().buttons.count
        XCTAssertGreaterThanOrEqual(count, 5,
                                    "Navigation overlay should list the main destinations")
        for index in 0 ..< count {
            let label = tapDestination(at: index)

            // Each destination should render at least one descendant element.
            let anyElement = app.descendants(matching: .any).element(boundBy: 0)
            XCTAssertTrue(anyElement.waitForExistence(timeout: 3),
                          "Destination '\(label)' should render accessible content")
        }
    }

    /// Navigating to each destination and back does not leave the app in a
    /// broken state.
    func testNavigationRoundTrip() {
        let count = openNavigationDestinations().buttons.count
        for index in 0 ..< count {
            tapDestination(at: index)
        }
        // Return to the first destination.
        tapDestination(at: 0)

        XCTAssertTrue(app.buttons["command.navigation"].waitForExistence(timeout: 3),
                      "Command bar should still exist after round-trip navigation")
        let buttons = app.buttons.allElementsBoundByIndex
        let visibleButtons = buttons.filter { $0.exists && $0.isHittable }
        XCTAssertFalse(visibleButtons.isEmpty,
                       "Home surface should have interactive elements after round-trip")
    }

    // MARK: - VoiceOver Traits

    /// Home surface has visible static text elements with content.
    func testStaticTextElementsHaveContent() {
        let staticTexts = app.staticTexts.allElementsBoundByIndex
        let visibleTexts = staticTexts.filter { $0.exists && !$0.label.isEmpty }
        XCTAssertFalse(visibleTexts.isEmpty,
                       "Home surface should have at least one visible static text element")
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
