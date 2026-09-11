// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Screenshot walk — captures every reachable screen so CI publishes a
// gallery of what the app looks like on this commit.
//
// Not a visual regression test: nothing is compared against a baseline.
// The assertions only prove that the walk produced captures and that the
// destination captures are not the same frame over and over (which is what
// a stuck overlay or a dead tap would produce). PNGs go to the directory
// named by `VAUCHI_SCREENSHOT_DIR` (reaches the runner as
// `TEST_RUNNER_VAUCHI_SCREENSHOT_DIR` on the xcodebuild command line) and
// always to the xcresult as attachments, so a run without the variable
// still leaves the gallery in the result bundle.
//
// Drives the app only through the stable frontend a11y identifiers
// (`command.*`, `navigationDestinations`) — never core action ids or
// localized labels, which are Core's to change.

import XCTest

final class ScreenshotWalkUITests: XCTestCase {
    var app: XCUIApplication!
    var captures: [Capture] = []
    var outputDirectory: URL?

    struct Capture {
        let name: String
        let byteCount: Int
        let hash: Int
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        captures = []
        outputDirectory = makeOutputDirectory()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Onboarding

    /// Walks onboarding from the first launch: screenshot, drive the primary
    /// command, repeat until the home surface shows its destinations, the
    /// primary command runs out, or eight screens are captured.
    ///
    /// Onboarding runs first, by name. `--reset-for-testing` seeds an
    /// identity and nothing ever wipes one, so onboarding is only on screen
    /// for the first launch after an install — which the simulator job's
    /// `simctl erase all` provides exactly once. XCTest orders a class's
    /// tests alphabetically and `-only-testing` ignores a custom
    /// `defaultTestSuite`, so the numbers carry the order.
    func test1OnboardingFlow() throws {
        app.launchArguments = []
        app.launch()

        let primary = app.buttons["command.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15),
                      "First launch should land on onboarding with a primary command")

        // The command bar's navigation button is there from the welcome
        // screen on, so it says nothing about home; the destinations
        // container (a persistent bar) does, and where the shell has none
        // the walk runs its budget out a few screens past home.
        for step in 0 ..< 8 {
            settle()
            capture(screenSlug())
            if navigationDestinations.exists {
                if step == 0 {
                    throw XCTSkip("An identity already exists, so onboarding is not on screen; "
                        + "only on a fresh install (CI erases the simulator first)")
                }
                break
            }
            fillNameFieldIfPresent()
            guard primary.waitForExistence(timeout: 5), primary.isEnabled else { break }
            primary.tap()
        }

        XCTAssertGreaterThanOrEqual(captures.count, 2,
                                    "Onboarding should yield the welcome screen and at least one more step")
        assertCapturesWritten()
    }

    // MARK: - Destinations

    /// Screenshots home, the navigation overlay, every destination it lists,
    /// and the secondary-actions overlay.
    func test2Destinations() {
        app.launchArguments = ["--reset-for-testing"]
        app.launch()

        let navigation = app.buttons["command.navigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 15),
                      "Command bar should appear after --reset-for-testing identity seeding")
        settle()
        capture("home")

        let containersAtRest = destinationContainers.count
        let overlay = openOverlay(containersAtRest: containersAtRest)
        settle()
        capture("navigation")

        let labels = overlay.buttons.allElementsBoundByIndex.map(\.label)
        var destinationCaptures = 0
        for (index, label) in labels.enumerated() where !looksLikeSymbolName(label) {
            let container = openOverlay(containersAtRest: containersAtRest)
            let buttons = container.buttons.allElementsBoundByIndex
            guard index < buttons.count else { break }
            buttons[index].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = wait(destinationContainers, until: "count == \(containersAtRest)", timeout: 3)
            settle()
            capture(label)
            destinationCaptures += 1
        }
        XCTAssertGreaterThanOrEqual(destinationCaptures, 3,
                                    "Overlay should list at least three destinations "
                                        + "(saw \(labels))")

        // Back on the first destination: the last one walked is a leaf
        // that may not offer secondary actions.
        let container = openOverlay(containersAtRest: containersAtRest)
        container.buttons.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = wait(destinationContainers, until: "count == \(containersAtRest)", timeout: 3)
        captureSecondaryActions()

        let distinct = Set(captures.map { "\($0.byteCount)-\($0.hash)" })
        XCTAssertGreaterThanOrEqual(distinct.count, 3,
                                    "At least three captures should differ; identical frames "
                                        + "mean the walk never left one screen")
        assertCapturesWritten()
    }
}
