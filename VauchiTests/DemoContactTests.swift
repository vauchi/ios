// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for the live demo-contact init hook.
//
// Other demo-contact operations (state queries, update trigger, dismiss,
// restore) are driven by core ScreenModels under Humble-UI; their
// repository wrappers were only exercised by tests and have been retired.

@testable import Vauchi
import XCTest

/// Tests for live demo-contact surface.
/// Based on: features/demo_contact.feature
final class DemoContactTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Demo Contact Init Hook

    // Based on: features/demo_contact.feature @demo-appear

    /// Scenario: Demo contact appears for users with no contacts
    func testDemoContactAppearsForUsersWithNoContacts() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let demoContact = try XCTUnwrap(
            repo.initDemoContactIfNeeded(),
            "Demo contact should appear for users with no contacts"
        )

        XCTAssertEqual(demoContact.displayName, "Vauchi Tips")
        XCTAssertTrue(demoContact.isDemo, "Contact should be marked as demo")
    }

    /// Scenario: Demo contact is visually distinct
    func testDemoContactIsVisuallyDistinct() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let demoContact = try XCTUnwrap(repo.initDemoContactIfNeeded())

        XCTAssertTrue(demoContact.isDemo, "Demo contact should have isDemo flag")
    }

    /// Scenario: Demo contact has rotating tips
    func testDemoContactHasTips() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let demoContact = try XCTUnwrap(repo.initDemoContactIfNeeded())

        XCTAssertFalse(demoContact.tipTitle.isEmpty, "Tip title should not be empty")
        XCTAssertFalse(demoContact.tipContent.isEmpty, "Tip content should not be empty")
        XCTAssertFalse(demoContact.tipCategory.isEmpty, "Tip category should not be empty")
    }
}
