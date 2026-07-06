// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for VauchiRepository live frontend-infrastructure surface.
//
// Domain CRUD wrappers are retired; they are covered at the core engine
// level or through Humble-UI core-driven screens. What remains here is
// identity bootstrap and the identity-presence flag.

@testable import Vauchi
import XCTest

/// Tests for VauchiRepository live surface.
/// Based on: features/identity_management.feature
final class VauchiRepositoryTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Identity Management Tests

    // Based on: features/identity_management.feature

    /// Scenario: First launch - no identity exists
    func testNoIdentityOnFirstLaunch() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        XCTAssertFalse(repo.hasIdentity(), "Should have no identity on first launch")
    }

    /// Scenario: Create new identity flips the presence flag
    func testCreateIdentity() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        XCTAssertFalse(repo.hasIdentity())

        try repo.createIdentity(displayName: "Alice")

        XCTAssertTrue(repo.hasIdentity(), "Should have identity after creation")
    }

    /// Scenario: Cannot create identity twice
    ///
    /// Per ADR-044, `MobileError` no longer distinguishes
    /// "already initialized" — core returns `MobileError.Other { detail:
    /// "Already initialized" }`, which the repository maps to
    /// `.internalError(detail)`. The observable contract is that the second
    /// `createIdentity` throws with an explanatory message.
    func testCannotCreateIdentityTwice() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        XCTAssertThrowsError(try repo.createIdentity(displayName: "Bob")) { error in
            guard case let VauchiRepositoryError.internalError(detail) = error else {
                XCTFail("Expected internalError, got \(error)")
                return
            }
            XCTAssertTrue(
                detail.localizedCaseInsensitiveContains("already"),
                "Expected detail to mention 'already', got \(detail)"
            )
        }
    }
}
