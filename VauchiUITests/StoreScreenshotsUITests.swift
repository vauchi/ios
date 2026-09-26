// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// App Store screenshots — restores the fictional "Alex Morgan" fixture
// (e2e `seed-contacts --count 12 --seed 7`, reserved 555-01xx numbers and
// example.* domains) and captures the store set. Run by the manual
// `screenshots:store` job on the 6.9" simulator.
//
// Unlike `ScreenshotWalkUITests`, this taps rows by their English labels:
// rows carry no stable identifiers, and the store set is English-only.
// The restore goes through `--import-backup`, never the system document
// picker (CC-23).

import XCTest

final class StoreScreenshotsUITests: XCTestCase {
    private let fixturePassword = "screens-2026"
    private var app: XCUIApplication!
    private var outputDirectory: URL?
    private var captureCount = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        outputDirectory = try makeOutputDirectory()
    }

    func testStoreScreenshots() throws {
        // Needs a freshly erased simulator; `test:ui` runs the whole target
        // on a simulator that already holds an identity.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VAUCHI_STORE_SCREENSHOTS"] == "1",
                          "Runs only in the screenshots:store job")
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "store-screens", withExtension: "vauchibackup"),
            "The fixture backup must be bundled with the UI tests"
        )
        app.launchArguments = ["--import-backup", fixture.path]
        app.launch()

        let primary = app.buttons["command.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 20),
                      "A fresh install should open on the welcome screen")
        settle()
        capture("welcome")

        tapLabel("Restore from backup")
        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10),
                      "The fixture should stand in for the file pick and reach the password step")
        password.tap()
        // No trailing Return: submitting re-renders the step and the typed
        // password never reaches Restore (store job 16742956860).
        password.typeText(fixturePassword)
        XCTAssertTrue(wait(for: primary, enabled: true, timeout: 5),
                      "Restore should enable once the password is typed")
        primary.tap()

        // Onboarding already shows a one-tab bar, so the restored home is
        // recognised by the fixture's own name.
        XCTAssertTrue(app.staticTexts["Alex Morgan"].waitForExistence(timeout: 30),
                      "Restoring the fixture should land on Alex Morgan's card")
        settle()
        capture("my-card")

        tapLabel("Contacts")
        settle()
        capture("contacts")

        tapLabel("Alexander Conroy")
        settle()
        capture("contact-detail")

        tapLabel("Exchange")
        settle()
        // The exchange flow opens on "Assign to Groups" (store job
        // 16751597117); its primary action skips it.
        if primary.waitForExistence(timeout: 5) { primary.tap() }
        settle()
        // The simulator reports no camera, so Core recommends Link and offers
        // no Glance/QR mode (element tree, store job 16751717284). The mode
        // picker is the last screen the simulator can show.
        XCTAssertTrue(labelled("Other ways to connect").waitForExistence(timeout: 10),
                      "Skipping group assignment should reach the exchange mode picker")
        capture("exchange-mode")

        XCTAssertEqual(captureCount, 5, "Every store screen should have been captured")
    }

    private func wait(for element: XCUIElement, enabled: Bool, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isEnabled == %@", NSNumber(value: enabled)),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// A row can expose its title and subtitle as one combined label
    /// ("Glance, Recommended · …"), so a prefix match is accepted too.
    private func labelled(_ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
            .firstMatch
    }

    /// On a miss, the element tree goes into the result bundle and the log,
    /// so the next fix reads the hierarchy instead of guessing it.
    private func tapLabel(_ label: String) {
        let element = labelled(label)
        guard element.waitForExistence(timeout: 10) else {
            let tree = app.debugDescription
            let attachment = XCTAttachment(string: tree)
            attachment.name = "hierarchy-missing-\(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("[store-screenshots] element tree when \(label) was missing:\n\(tree)")
            XCTFail("Missing \(label)")
            return
        }
        element.tap()
    }

    /// Transitions leave nothing to poll for, and a mid-animation frame is
    /// blurred in a store listing.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func capture(_ slug: String) {
        captureCount += 1
        let name = String(format: "%02d-%@.png", captureCount, slug)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let outputDirectory {
            XCTAssertNoThrow(try png.write(to: outputDirectory.appendingPathComponent(name)))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeOutputDirectory() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["VAUCHI_SCREENSHOT_DIR"], !path.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: path).appendingPathComponent("store")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
