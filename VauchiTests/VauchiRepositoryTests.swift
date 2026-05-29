// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiRepositoryTests.swift
// Tests for VauchiRepository - based on features/*.feature Gherkin scenarios

import Darwin
@testable import Vauchi
import XCTest

/// Tests for VauchiRepository
/// Based on: features/identity_management.feature, features/contact_card_management.feature
final class VauchiRepositoryTests: XCTestCase {
    var tempDir: URL!

    /// Local dev relay URL for integration tests (started via `just dev-relay`)
    private static let localRelayUrl = "http://127.0.0.1:8080"

    /// Skip test if local relay is not running.
    /// Uses a quick TCP connect check to port 8080.
    private func requireLocalRelay() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw XCTSkip("Local relay not available — start with: just dev-relay")
        }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(8080).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            throw XCTSkip("Local relay not running at \(Self.localRelayUrl) — start with: just dev-relay")
        }
    }

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

    // MARK: - Identity Management Tests

    // Based on: features/identity_management.feature

    /// Scenario: First launch - no identity exists
    func testNoIdentityOnFirstLaunch() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        XCTAssertFalse(repo.hasIdentity(), "Should have no identity on first launch")
    }

    /// Scenario: Create new identity with display name
    func testCreateIdentity() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        XCTAssertFalse(repo.hasIdentity())

        try repo.createIdentity(displayName: "Alice")

        XCTAssertTrue(repo.hasIdentity(), "Should have identity after creation")
        XCTAssertEqual(try repo.getDisplayName(), "Alice")
    }

    /// Scenario: Identity generates Ed25519 keypair
    func testIdentityHasPublicId() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let publicId = try repo.getPublicId()

        XCTAssertFalse(publicId.isEmpty, "Public ID should not be empty")
        // Ed25519 public key is 32 bytes = 64 hex chars
        XCTAssertEqual(publicId.count, 64, "Public ID should be 64 hex characters")
    }

    /// Scenario: Identity persists across sessions
    func testIdentityPersistsAcrossSessions() throws {
        // First session - create identity
        do {
            let repo = try VauchiRepository(dataDir: tempDir.path)
            try repo.createIdentity(displayName: "Alice")
        }

        // Second session - identity should exist
        let repo2 = try VauchiRepository(dataDir: tempDir.path)
        XCTAssertTrue(repo2.hasIdentity(), "Identity should persist across sessions")
        XCTAssertEqual(try repo2.getDisplayName(), "Alice")
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

    // MARK: - Contact Card Tests

    // Based on: features/contact_card_management.feature

    /// Scenario: Initial card has display name only
    func testInitialCardHasDisplayName() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let card = try repo.getOwnCard()

        XCTAssertEqual(card.displayName, "Alice")
        XCTAssertTrue(card.fields.isEmpty, "Initial card should have no fields")
    }

    /// Scenario: Add email field to card
    func testAddEmailField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        try repo.addField(type: .email, label: "Work", value: "alice@company.com")

        let card = try repo.getOwnCard()
        XCTAssertEqual(card.fields.count, 1)
        XCTAssertEqual(card.fields[0].fieldType, .email)
        XCTAssertEqual(card.fields[0].label, "Work")
        XCTAssertEqual(card.fields[0].value, "alice@company.com")
    }

    /// Scenario: Add phone field to card
    func testAddPhoneField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        try repo.addField(type: .phone, label: "Mobile", value: "+1234567890")

        let card = try repo.getOwnCard()
        XCTAssertEqual(card.fields.count, 1)
        XCTAssertEqual(card.fields[0].fieldType, .phone)
        XCTAssertEqual(card.fields[0].label, "Mobile")
        XCTAssertEqual(card.fields[0].value, "+1234567890")
    }

    /// Scenario: Update field value
    func testUpdateFieldValue() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
        try repo.addField(type: .phone, label: "Mobile", value: "+1234567890")

        try repo.updateField(label: "Mobile", newValue: "+0987654321")

        let card = try repo.getOwnCard()
        XCTAssertEqual(card.fields[0].value, "+0987654321")
    }

    /// Scenario: Remove field from card
    func testRemoveField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
        try repo.addField(type: .email, label: "Work", value: "alice@company.com")

        let removed = try repo.removeField(label: "Work")

        XCTAssertTrue(removed, "removeField should return true")
        let card = try repo.getOwnCard()
        XCTAssertTrue(card.fields.isEmpty, "Field should be removed")
    }

    /// Scenario: Remove non-existent field returns false
    func testRemoveNonExistentField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let removed = try repo.removeField(label: "NonExistent")

        XCTAssertFalse(removed, "Removing non-existent field should return false")
    }

    /// Scenario: Update display name
    func testUpdateDisplayName() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        try repo.setDisplayName("Alice Smith")

        XCTAssertEqual(try repo.getDisplayName(), "Alice Smith")
        let card = try repo.getOwnCard()
        XCTAssertEqual(card.displayName, "Alice Smith")
    }

    // MARK: - Contact Exchange Tests

    // Based on: features/contact_exchange.feature

    /// Scenario: Generate exchange QR code
    func testGenerateExchangeQr() throws {
        throw XCTSkip(
            "Blocked on exchange session typed-method migration. "
                + "createIdentity now goes through PlatformAppEngine while "
                + "createQrExchangeManual remains on legacy VauchiPlatform "
                + "(stateful session, deferred from dispatch per "
                + "_private/docs/problems/2026-04-28-collapse-vauchi-platform-"
                + "into-app-engine/). Restore after exchange migration."
        )
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let sessionData = try repo.generateExchangeQrWithSession()
        let exchangeData = sessionData.exchangeData

        XCTAssertTrue(exchangeData.qrData.hasPrefix("wb://"), "QR data should start with wb://")
        XCTAssertFalse(exchangeData.publicId.isEmpty)
        XCTAssertGreaterThan(exchangeData.expiresAt, UInt64(Date().timeIntervalSince1970))
    }

    /// Scenario: QR code expires after 5 minutes
    func testQrCodeExpiration() throws {
        throw XCTSkip(
            "Blocked on exchange session typed-method migration — "
                + "see testGenerateExchangeQr for details."
        )
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let sessionData = try repo.generateExchangeQrWithSession()
        let exchangeData = sessionData.exchangeData
        let now = UInt64(Date().timeIntervalSince1970)

        // Should expire in ~5 minutes (300 seconds)
        let expiresIn = exchangeData.expiresAt - now
        XCTAssertGreaterThanOrEqual(expiresIn, 295, "Should expire in at least 295 seconds")
        XCTAssertLessThanOrEqual(expiresIn, 305, "Should expire in at most 305 seconds")
    }

    // MARK: - Contact Management Tests

    // Based on: features/contacts_management.feature

    /// Scenario: Empty contacts list on first launch
    func testEmptyContactsList() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let contacts = try repo.listContacts()

        XCTAssertTrue(contacts.isEmpty, "Contact list should be empty initially")
        XCTAssertEqual(try repo.contactCount(), 0)
    }

    /// Scenario: Search contacts returns empty for no matches
    func testSearchContactsEmpty() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let results = try repo.searchContacts(query: "Bob")

        XCTAssertTrue(results.isEmpty, "Search should return empty for no matches")
    }

    /// Scenario: Get non-existent contact returns nil
    func testGetNonExistentContact() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let contact = try repo.getContact(id: "nonexistent")

        XCTAssertNil(contact, "Non-existent contact should return nil")
    }

    // MARK: - Backup Tests

    // Based on: features/identity_management.feature

    /// Scenario: Export encrypted backup
    func testExportBackup() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
        try repo.addField(type: .email, label: "Work", value: "alice@company.com")

        let backup = try repo.exportBackup(password: "correct-horse-battery-staple")

        XCTAssertFalse(backup.isEmpty, "Backup should not be empty")
        // Backup is base64 encoded — assert non-empty decoded payload to ensure
        // it isn't just a base64 representation of zero bytes.
        let decoded = try XCTUnwrap(Data(base64Encoded: backup), "Backup should be valid base64")
        XCTAssertGreaterThan(decoded.count, 0, "Decoded backup must contain at least the encrypted payload")
    }

    /// Scenario: Import backup restores identity
    func testImportBackup() throws {
        var backupData: String!

        // Create identity and export backup
        do {
            let repo = try VauchiRepository(dataDir: tempDir.path)
            try repo.createIdentity(displayName: "Alice")
            try repo.addField(type: .email, label: "Work", value: "alice@company.com")
            backupData = try repo.exportBackup(password: "correct-horse-battery-staple")
        }

        // Create new repository and import backup
        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: newDir) }

        let repo2 = try VauchiRepository(dataDir: newDir.path)
        try repo2.importBackup(data: backupData, password: "correct-horse-battery-staple")

        XCTAssertTrue(repo2.hasIdentity())
        XCTAssertEqual(try repo2.getDisplayName(), "Alice")
    }

    // MARK: - Sync Tests

    // Based on: features/sync_updates.feature

    /// Scenario: Initial sync status is idle
    func testInitialSyncStatusIsIdle() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        XCTAssertEqual(repo.getSyncStatus(), .idle)
    }

    // MARK: - Social Networks Tests

    /// Scenario: List available social networks
    func testListSocialNetworks() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        let networks = repo.listSocialNetworks()

        XCTAssertFalse(networks.isEmpty, "Should have default social networks")
    }

    /// Scenario: Get profile URL for social network
    func testGetProfileUrl() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        let url = repo.getProfileUrl(networkId: "github", username: "octocat")

        XCTAssertEqual(url, "https://github.com/octocat")
    }

    // MARK: - Contact Exchange Tests (Full Flow)

    // Based on: features/contact_exchange.feature

    /// Scenario: Complete contact exchange between two users
    /// Tests the full QR exchange flow between Alice and Bob
    /// Note: Requires a running relay server
    func testCompleteContactExchange() throws {
        try requireLocalRelay()

        // Create Alice's repository
        let aliceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliceDir) }

        let aliceRepo = try VauchiRepository(dataDir: aliceDir.path, relayUrl: Self.localRelayUrl)
        try aliceRepo.createIdentity(displayName: "Alice")
        try aliceRepo.addField(type: .email, label: "Work", value: "alice@company.com")

        // Create Bob's repository
        let bobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bobDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bobDir) }

        let bobRepo = try VauchiRepository(dataDir: bobDir.path, relayUrl: Self.localRelayUrl)
        try bobRepo.createIdentity(displayName: "Bob")
        try bobRepo.addField(type: .phone, label: "Mobile", value: "+1234567890")

        // Alice generates QR code (with session)
        let aliceSession = try aliceRepo.generateExchangeQrWithSession()
        XCTAssertFalse(aliceSession.exchangeData.qrData.isEmpty)

        // Bob generates QR and scans Alice's QR using the held session
        let bobSession = try bobRepo.generateExchangeQrWithSession()
        try bobSession.session.processQr(qrData: aliceSession.exchangeData.qrData)
        let bobPeerName = bobSession.session.peerDisplayName() ?? "Unknown"
        XCTAssertEqual(bobPeerName, "Alice")
        try bobSession.session.confirmProximity()
        try bobSession.session.theyScannedOurQr()
        try bobSession.session.performKeyAgreement()
        try bobSession.session.completeCardExchange(theirCardName: bobPeerName)
        let bobResult = try bobRepo.finalizeExchange(session: bobSession.session)
        XCTAssertTrue(bobResult.success, "Bob's exchange should succeed: \(bobResult.errorMessage ?? "no error")")
        XCTAssertEqual(bobResult.contactName, "Alice")

        // Bob now has Alice as a contact
        let bobContacts = try bobRepo.listContacts()
        XCTAssertEqual(bobContacts.count, 1)
        XCTAssertEqual(bobContacts[0].displayName, "Alice")

        // Alice scans Bob's QR using her held session
        try aliceSession.session.processQr(qrData: bobSession.exchangeData.qrData)
        let alicePeerName = aliceSession.session.peerDisplayName() ?? "Unknown"
        XCTAssertEqual(alicePeerName, "Bob")
        try aliceSession.session.confirmProximity()
        try aliceSession.session.theyScannedOurQr()
        try aliceSession.session.performKeyAgreement()
        try aliceSession.session.completeCardExchange(theirCardName: alicePeerName)
        let aliceResult = try aliceRepo.finalizeExchange(session: aliceSession.session)
        XCTAssertTrue(aliceResult.success, "Alice's exchange should succeed: \(aliceResult.errorMessage ?? "no error")")
        XCTAssertEqual(aliceResult.contactName, "Bob")

        // Alice now has Bob as a contact
        let aliceContacts = try aliceRepo.listContacts()
        XCTAssertEqual(aliceContacts.count, 1)
        XCTAssertEqual(aliceContacts[0].displayName, "Bob")
    }

    /// Scenario: Exchange with expired QR code fails gracefully
    func testExchangeWithInvalidQrFails() throws {
        throw XCTSkip(
            "Blocked on exchange session typed-method migration — "
                + "see testGenerateExchangeQr for details."
        )
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // Try to process invalid QR data on a fresh session
        let sessionData = try repo.generateExchangeQrWithSession()
        XCTAssertThrowsError(try sessionData.session.processQr(qrData: "invalid_qr_data"))
    }

    /// Scenario: Cannot exchange with self
    /// Note: Requires a running relay server
    func testCannotExchangeWithSelf() throws {
        try requireLocalRelay()

        let repo = try VauchiRepository(dataDir: tempDir.path, relayUrl: Self.localRelayUrl)
        try repo.createIdentity(displayName: "Alice")

        let sessionData = try repo.generateExchangeQrWithSession()

        // Try to complete exchange with own QR on the same session
        try sessionData.session.processQr(qrData: sessionData.exchangeData.qrData)
        try sessionData.session.confirmProximity()
        try sessionData.session.theyScannedOurQr()
        try sessionData.session.performKeyAgreement()
        try sessionData.session.completeCardExchange(theirCardName: "Alice")
        let result = try repo.finalizeExchange(session: sessionData.session)

        // Exchange with self should fail
        XCTAssertFalse(result.success, "Should not be able to exchange with self")
    }
}
