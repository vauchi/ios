// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

extension ScreenshotWalkUITests {
    var navigationDestinations: XCUIElement {
        destinationContainers.firstMatch
    }

    /// Every container carrying the destinations identifier. There can be
    /// two at once: a persistent bottom tab bar and the opened overlay.
    var destinationContainers: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "navigationDestinations")
    }

    // MARK: - Capturing

    /// Writes the current screen as `NN-<slug>.png` and attaches it to the
    /// result bundle.
    func capture(_ slug: String) {
        let index = captures.count + 1
        let name = String(format: "%02d-%@.png", index, slugify(slug))
        let png = XCUIScreen.main.screenshot().pngRepresentation

        if let outputDirectory {
            let url = outputDirectory.appendingPathComponent(name)
            XCTAssertNoThrow(try png.write(to: url), "Should write \(url.path)")
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        captures.append(Capture(name: name, byteCount: png.count, hash: png.hashValue))
    }

    /// Screen names come from the a11y tree, so they are localized and free
    /// form; the file name only has to be stable and filesystem-safe.
    func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        var slug = ""
        var pendingDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return slug.isEmpty ? "screen" : String(slug.prefix(40))
    }

    /// The first non-empty text on screen — the surface title on every
    /// core-driven screen — names the onboarding steps.
    func screenSlug() -> String {
        let title = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .first { !$0.isEmpty }
        return title ?? "step"
    }

    func makeOutputDirectory() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["VAUCHI_SCREENSHOT_DIR"],
              !path.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: path).appendingPathComponent(testDirectoryName)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `test1OnboardingFlow` → `onboarding-flow`, so each walk owns a
    /// folder and their `NN-` prefixes never collide.
    private var testDirectoryName: String {
        let selector = name.split(separator: " ").last.map(String.init) ?? name
        let method = selector.replacingOccurrences(of: "]", with: "")
        let trimmed = method.replacingOccurrences(of: "^test[0-9]*", with: "", options: .regularExpression)
        var slug = ""
        for character in trimmed {
            if character.isUppercase, !slug.isEmpty { slug.append("-") }
            slug.append(character.lowercased())
        }
        return slug
    }

    func assertCapturesWritten() {
        XCTAssertFalse(captures.isEmpty, "Walk should capture at least one screen")
        guard let outputDirectory else { return }
        for capture in captures {
            let path = outputDirectory.appendingPathComponent(capture.name).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Missing \(path)")
        }
    }

    // MARK: - Driving

    /// SwiftUI transitions and the overlay's ease-out leave nothing in the
    /// hierarchy to poll for; a screenshot taken mid-animation is a blurred
    /// frame, so the walk waits them out instead.
    func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    func wait(_ query: XCUIElementQuery, until predicate: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate),
                                                    object: query)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Opens the navigation overlay unless it is already open and returns the
    /// container listing the most destinations — the overlay, when a shorter
    /// persistent tab bar also carries the identifier.
    func openOverlay(containersAtRest: Int) -> XCUIElement {
        if destinationContainers.count <= containersAtRest {
            let navigation = app.buttons["command.navigation"]
            XCTAssertTrue(navigation.waitForExistence(timeout: 5),
                          "Navigation command should exist on every main destination")
            navigation.tap()
            XCTAssertTrue(wait(destinationContainers, until: "count > \(containersAtRest)", timeout: 5),
                          "Navigation overlay should list destinations")
            // The container exists before its rows do; a button bound by
            // index during the fade-in resolved to nothing once.
            settle()
        }
        let containers = destinationContainers.allElementsBoundByIndex
        let richest = containers.max { $0.buttons.count < $1.buttons.count }
        return richest ?? navigationDestinations
    }

    /// Onboarding asks for a display name; the field is the only text input
    /// on that step. Return dismisses the keyboard so the command bar it
    /// covered is hittable again.
    func fillNameFieldIfPresent() {
        let field = app.textFields.firstMatch
        guard field.exists else { return }
        field.tap()
        field.typeText("Test User\n")
        settle()
        capture("\(screenSlug())-filled")
    }

    func captureSecondaryActions() {
        let secondary = app.buttons["command.secondary"]
        guard secondary.waitForExistence(timeout: 3), secondary.isEnabled else {
            return
        }
        secondary.tap()
        settle()
        capture("secondary-actions")
    }

    /// An SF Symbol name, e.g. `person.crop.rectangle.fill` — lowercase
    /// segments joined by dots, which no human-facing label ever is.
    func looksLikeSymbolName(_ label: String) -> Bool {
        label.range(of: "^[a-z][a-z0-9]*(\\.[a-z0-9]+)+$", options: .regularExpression) != nil
    }
}
