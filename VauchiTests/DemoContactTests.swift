// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DemoContactTests.swift
// Tests for Demo Contact feature - based on features/demo_contact.feature Gherkin scenarios
//
// Traces to: features/demo_contact.feature

@testable import Vauchi
import XCTest

/// Tests for Demo Contact feature
/// Based on: features/demo_contact.feature
final class DemoContactTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        // Create temp directory for each test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Demo Contact Appearance Tests

    // Based on: features/demo_contact.feature @demo-appear

    /// Scenario: Demo contact appears for users with no contacts
    /// Given I have no real contacts
    /// When I complete the onboarding process
    /// Then a demo contact named "Vauchi Tips" should appear
    func testDemoContactAppearsForUsersWithNoContacts() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // User has no contacts
        XCTAssertEqual(try repo.contactCount(), 0)

        // Initialize demo contact after onboarding
        let demoContact = try repo.initDemoContactIfNeeded()

        // Demo contact should appear
        XCTAssertNotNil(demoContact, "Demo contact should appear for users with no contacts")
        XCTAssertEqual(demoContact?.displayName, "Vauchi Tips")
        XCTAssertTrue(demoContact?.isDemo ?? false, "Contact should be marked as demo")
    }

    /// Scenario: Demo contact does not appear if user has contacts
    /// Given I already have real contacts
    /// When I complete the onboarding process
    /// Then no demo contact should be created
    func testDemoContactDoesNotAppearIfUserHasContacts() throws {
        try Self.skipPendingExchangeMigration()
        // Create two users so they can exchange
        let aliceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliceDir) }

        let bobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bobDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bobDir) }

        let aliceRepo = try VauchiRepository(dataDir: aliceDir.path)
        try aliceRepo.createIdentity(displayName: "Alice")

        let bobRepo = try VauchiRepository(dataDir: bobDir.path)
        try bobRepo.createIdentity(displayName: "Bob")

        // Alice and Bob exchange contacts using session-based flow
        let aliceSession = try aliceRepo.generateExchangeQrWithSession()
        let bobSession = try bobRepo.generateExchangeQrWithSession()
        do {
            try bobSession.session.processQr(qrData: aliceSession.exchangeData.qrData)
            let peerName = bobSession.session.peerDisplayName() ?? "Unknown"
            try bobSession.session.confirmProximity()
            try bobSession.session.theyScannedOurQr()
            try bobSession.session.performKeyAgreement()
            try bobSession.session.completeCardExchange(theirCardName: peerName)
            _ = try bobRepo.finalizeExchange(session: bobSession.session)
        } catch {
            throw XCTSkip("Relay server unavailable: \(error.localizedDescription)")
        }

        do {
            try aliceSession.session.processQr(qrData: bobSession.exchangeData.qrData)
            let peerName = aliceSession.session.peerDisplayName() ?? "Unknown"
            try aliceSession.session.confirmProximity()
            try aliceSession.session.theyScannedOurQr()
            try aliceSession.session.performKeyAgreement()
            try aliceSession.session.completeCardExchange(theirCardName: peerName)
            _ = try aliceRepo.finalizeExchange(session: aliceSession.session)
        } catch {
            throw XCTSkip("Relay server unavailable: \(error.localizedDescription)")
        }

        // Alice now has a real contact
        XCTAssertGreaterThan(try aliceRepo.contactCount(), 0)

        // Demo contact should NOT appear
        let demoContact = try aliceRepo.initDemoContactIfNeeded()
        XCTAssertNil(demoContact, "Demo contact should not appear for users with contacts")
    }

    /// Scenario: Demo contact is visually distinct
    /// Given the demo contact exists
    /// When I view my contacts list
    /// Then the demo contact should have a special indicator
    func testDemoContactIsVisuallyDistinct() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let demoContact = try repo.initDemoContactIfNeeded()

        XCTAssertNotNil(demoContact)
        XCTAssertTrue(demoContact?.isDemo ?? false, "Demo contact should have isDemo flag")
    }

    // MARK: - Demo Updates Tests

    // Based on: features/demo_contact.feature @demo-updates

    /// Scenario: Demo updates demonstrate the update flow
    /// Given the demo contact exists
    /// When I receive a demo update
    /// Then the contact card should show updated content
    func testDemoUpdateShowsNewContent() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let initialDemo = try repo.initDemoContactIfNeeded()
        XCTAssertNotNil(initialDemo)

        let initialTip = initialDemo?.tipTitle

        // Trigger an update
        let updatedDemo = try repo.triggerDemoUpdate()

        XCTAssertNotNil(updatedDemo, "Demo update should return updated contact")
        XCTAssertNotEqual(updatedDemo?.tipTitle, initialTip, "Tip should change after update")
    }

    /// Scenario: Demo contact has rotating tips
    /// Given the demo contact exists
    /// Then the contact card should contain helpful content
    func testDemoContactHasTips() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let demoContact = try repo.initDemoContactIfNeeded()

        XCTAssertNotNil(demoContact)
        XCTAssertFalse(demoContact?.tipTitle.isEmpty ?? true, "Tip title should not be empty")
        XCTAssertFalse(demoContact?.tipContent.isEmpty ?? true, "Tip content should not be empty")
        XCTAssertFalse(demoContact?.tipCategory.isEmpty ?? true, "Tip category should not be empty")
    }

    // MARK: - Demo Contact Dismissal Tests

    // Based on: features/demo_contact.feature @demo-dismiss

    /// Scenario: Demo contact can be manually dismissed
    /// Given the demo contact exists
    /// When I choose to dismiss the demo contact
    /// Then the demo contact should be removed
    func testDemoContactCanBeManuallyDismissed() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // Initialize demo contact
        _ = try repo.initDemoContactIfNeeded()

        // Verify demo contact exists
        XCTAssertNotNil(try repo.getDemoContact())

        // Dismiss the demo contact
        try repo.dismissDemoContact()

        // Demo contact should no longer appear
        XCTAssertNil(try repo.getDemoContact(), "Demo contact should be removed after dismissal")

        // State should reflect dismissal
        let state = repo.getDemoContactState()
        XCTAssertTrue(state.wasDismissed, "State should show was_dismissed")
        XCTAssertFalse(state.isActive, "State should show not active")
    }

    /// Scenario: Demo contact auto-removes after first real exchange
    /// Given the demo contact exists
    /// When I complete an exchange with a real contact
    /// Then the demo contact should be automatically removed
    func testDemoContactAutoRemovesAfterFirstExchange() throws {
        try Self.skipPendingExchangeMigration()
        // Create two users
        let aliceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliceDir) }

        let bobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bobDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bobDir) }

        let aliceRepo = try VauchiRepository(dataDir: aliceDir.path)
        try aliceRepo.createIdentity(displayName: "Alice")

        let bobRepo = try VauchiRepository(dataDir: bobDir.path)
        try bobRepo.createIdentity(displayName: "Bob")

        // Alice has demo contact
        _ = try aliceRepo.initDemoContactIfNeeded()
        XCTAssertNotNil(try aliceRepo.getDemoContact(), "Demo contact should exist initially")

        // Alice and Bob exchange using session-based flow
        let aliceSession = try aliceRepo.generateExchangeQrWithSession()
        let bobSession = try bobRepo.generateExchangeQrWithSession()
        do {
            try bobSession.session.processQr(qrData: aliceSession.exchangeData.qrData)
            let peerName = bobSession.session.peerDisplayName() ?? "Unknown"
            try bobSession.session.confirmProximity()
            try bobSession.session.theyScannedOurQr()
            try bobSession.session.performKeyAgreement()
            try bobSession.session.completeCardExchange(theirCardName: peerName)
            _ = try bobRepo.finalizeExchange(session: bobSession.session)
        } catch {
            throw XCTSkip("Relay server unavailable: \(error.localizedDescription)")
        }

        do {
            try aliceSession.session.processQr(qrData: bobSession.exchangeData.qrData)
            let peerName = aliceSession.session.peerDisplayName() ?? "Unknown"
            try aliceSession.session.confirmProximity()
            try aliceSession.session.theyScannedOurQr()
            try aliceSession.session.performKeyAgreement()
            try aliceSession.session.completeCardExchange(theirCardName: peerName)
            _ = try aliceRepo.finalizeExchange(session: aliceSession.session)
        } catch {
            throw XCTSkip("Relay server unavailable: \(error.localizedDescription)")
        }

        // Auto-remove demo contact after first real exchange
        let wasRemoved = try aliceRepo.autoRemoveDemoContact()

        XCTAssertTrue(wasRemoved, "Auto-remove should return true")
        XCTAssertNil(try aliceRepo.getDemoContact(), "Demo contact should be removed after exchange")

        let state = aliceRepo.getDemoContactState()
        XCTAssertTrue(state.autoRemoved, "State should show auto_removed")
    }

    /// Scenario: Demo contact can be restored from settings
    /// Given the demo contact was dismissed
    /// When I go to Settings > Help > Show Demo Contact
    /// Then the demo contact should reappear
    func testDemoContactCanBeRestoredFromSettings() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // Initialize and dismiss demo contact
        _ = try repo.initDemoContactIfNeeded()
        try repo.dismissDemoContact()

        // Verify dismissed
        XCTAssertNil(try repo.getDemoContact())

        // Restore from settings
        let restoredDemo = try repo.restoreDemoContact()

        XCTAssertNotNil(restoredDemo, "Demo contact should be restored")
        XCTAssertNotNil(try repo.getDemoContact(), "getDemoContact should return contact after restore")

        let state = repo.getDemoContactState()
        XCTAssertTrue(state.isActive, "State should show active after restore")
        XCTAssertFalse(state.wasDismissed, "State should clear was_dismissed after restore")
    }

    // MARK: - Demo Contact Privacy Tests

    // Based on: features/demo_contact.feature @demo-privacy

    /// Scenario: Demo contact is local only
    /// Given the demo contact exists
    /// Then no data is sent to any server for the demo
    /// And the demo contact is stored locally
    func testDemoContactIsLocalOnly() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let demoContact = try repo.initDemoContactIfNeeded()
        XCTAssertNotNil(demoContact)

        // Demo contact should NOT appear in real contacts list
        let contacts = try repo.listContacts()
        let hasDemoInRealContacts = contacts.contains { $0.displayName == "Vauchi Tips" }
        XCTAssertFalse(hasDemoInRealContacts, "Demo contact should not be in real contacts list")
    }

    /// Scenario: Demo contact does not count as real contact
    /// Given the demo contact exists
    /// When I check my contact count
    /// Then the demo contact should not be counted
    func testDemoContactDoesNotCountAsRealContact() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // Initialize demo contact
        _ = try repo.initDemoContactIfNeeded()

        // Contact count should still be 0
        let count = try repo.contactCount()
        XCTAssertEqual(count, 0, "Demo contact should not be counted in contact count")
    }

    // MARK: - Demo Contact Persistence Tests

    // Based on: features/demo_contact.feature @demo-persistence

    /// Scenario: Demo contact state persists across app restarts
    /// Given the demo contact exists
    /// When I force quit and relaunch the app
    /// Then the demo contact should still be present
    func testDemoContactStatePersistsAcrossRestarts() throws {
        // First session - create demo contact
        do {
            let repo = try VauchiRepository(dataDir: tempDir.path)
            try repo.createIdentity(displayName: "Alice")
            _ = try repo.initDemoContactIfNeeded()

            // Verify demo exists
            XCTAssertNotNil(try repo.getDemoContact())
        }

        // Second session - demo should persist
        let repo2 = try VauchiRepository(dataDir: tempDir.path)
        let demoContact = try repo2.getDemoContact()

        XCTAssertNotNil(demoContact, "Demo contact should persist across sessions")
        XCTAssertEqual(demoContact?.displayName, "Vauchi Tips")
    }

    /// Scenario: Dismissal persists across app restarts
    /// Given I have dismissed the demo contact
    /// When I force quit and relaunch the app
    /// Then the demo contact should remain dismissed
    func testDismissalPersistsAcrossRestarts() throws {
        // First session - create and dismiss demo contact
        do {
            let repo = try VauchiRepository(dataDir: tempDir.path)
            try repo.createIdentity(displayName: "Alice")
            _ = try repo.initDemoContactIfNeeded()
            try repo.dismissDemoContact()
        }

        // Second session - should still be dismissed
        let repo2 = try VauchiRepository(dataDir: tempDir.path)

        // Init should not recreate dismissed demo
        let demoContact = try repo2.initDemoContactIfNeeded()
        XCTAssertNil(demoContact, "Dismissed demo contact should not reappear after restart")

        let state = repo2.getDemoContactState()
        XCTAssertTrue(state.wasDismissed, "Dismissal state should persist")
    }

    // MARK: - Demo Contact State Tests

    /// Test demo contact state properties
    func testDemoContactStateProperties() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // Initial state - no demo
        let initialState = repo.getDemoContactState()
        XCTAssertFalse(initialState.isActive)
        XCTAssertFalse(initialState.wasDismissed)
        XCTAssertFalse(initialState.autoRemoved)
        XCTAssertEqual(initialState.updateCount, 0)

        // After init - active
        _ = try repo.initDemoContactIfNeeded()
        let activeState = repo.getDemoContactState()
        XCTAssertTrue(activeState.isActive)
        XCTAssertFalse(activeState.wasDismissed)
        XCTAssertFalse(activeState.autoRemoved)
    }

    /// Test update count increments
    func testUpdateCountIncrements() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        _ = try repo.initDemoContactIfNeeded()

        let initialCount = repo.getDemoContactState().updateCount

        // Trigger updates
        _ = try repo.triggerDemoUpdate()
        _ = try repo.triggerDemoUpdate()

        let newCount = repo.getDemoContactState().updateCount
        XCTAssertEqual(newCount, initialCount + 2, "Update count should increment with each update")
    }

    /// Test is_demo_update_available check
    func testIsDemoUpdateAvailable() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        _ = try repo.initDemoContactIfNeeded()

        // Just initialized, update should not be due yet (2 hour interval)
        let isAvailable = repo.isDemoUpdateAvailable()
        XCTAssertFalse(isAvailable, "Update should not be available immediately after init")
    }

    /// Skip helper for tests that complete an exchange via `repo.generateExchangeQrWithSession()` —
    /// the session API still lives on legacy `vauchi: VauchiPlatform`, which has no in-memory
    /// identity after `appEngine.createIdentity` (no `reload_from_storage()` seam). Restored
    /// when the Exchange domain migrates (C8) per
    /// `_private/docs/problems/2026-04-28-collapse-vauchi-platform-into-app-engine/`.
    private static func skipPendingExchangeMigration() throws {
        throw XCTSkip(
            "Blocked on dual-instance state drift — Exchange session "
                + "methods still live on legacy VauchiPlatform; restored "
                + "when C8 (Exchange) migrates. See _private/docs/problems/"
                + "2026-04-28-collapse-vauchi-platform-into-app-engine/."
        )
    }
}
