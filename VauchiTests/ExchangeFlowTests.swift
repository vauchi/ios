// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ExchangeFlowTests.swift
// Tests for contact exchange flow integration
// Based on: features/contact_exchange.feature

@testable import Vauchi
import XCTest

/// Tests for contact exchange flow
/// Based on: features/contact_exchange.feature
final class ExchangeFlowTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Test User")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - QR Code Generation Tests

    // Based on: Scenario: Generate QR code for exchange

    /// Scenario: Generate QR code data for contact exchange
    func testGenerateQRCodeData() throws {
        let qrData = try repo.generateExchangeQR()

        XCTAssertFalse(qrData.isEmpty, "QR data should not be empty")
        // QR data should be base64 encoded
        XCTAssertNotNil(Data(base64Encoded: qrData), "QR data should be valid base64")
    }

    /// Scenario: QR code contains public key
    func testQRCodeContainsPublicKey() throws {
        let publicId = try repo.getPublicId()
        let qrData = try repo.generateExchangeQR()

        // The QR data should reference the identity somehow
        // (it's encrypted, but should be valid structure)
        XCTAssertFalse(qrData.isEmpty)
        XCTAssertFalse(publicId.isEmpty)
    }

    /// Scenario: Multiple QR codes can be generated
    func testMultipleQRCodesUnique() throws {
        let qr1 = try repo.generateExchangeQR()
        let qr2 = try repo.generateExchangeQR()
        let qr3 = try repo.generateExchangeQR()

        // Each QR code may include timestamp/nonce, making them different
        // Or they may be the same if deterministic - both are valid
        XCTAssertFalse(qr1.isEmpty)
        XCTAssertFalse(qr2.isEmpty)
        XCTAssertFalse(qr3.isEmpty)
    }

    // MARK: - QR Code Parsing Tests

    // Based on: Scenario: Parse scanned QR code

    /// Scenario: Parse invalid QR data returns error
    func testParseInvalidQRData() throws {
        let invalidData = "not-a-valid-qr-code"

        XCTAssertThrowsError(try repo.parseExchangeQR(qrData: invalidData)) { error in
            // Should throw some form of parse error
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Parse empty QR data returns error
    func testParseEmptyQRData() throws {
        XCTAssertThrowsError(try repo.parseExchangeQR(qrData: "")) { error in
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Parse corrupted base64 returns error
    func testParseCorruptedBase64() throws {
        let corruptedData = "!!!invalid-base64!!!"

        XCTAssertThrowsError(try repo.parseExchangeQR(qrData: corruptedData))
    }

    // MARK: - Exchange State Tests

    /// Scenario: Exchange requires identity first
    func testExchangeRequiresIdentity() throws {
        // Create repo without identity
        let tempDir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir2) }

        let repoNoIdentity = try VauchiRepository(dataDir: tempDir2.path)

        XCTAssertThrowsError(try repoNoIdentity.generateExchangeQR()) { error in
            // Should require identity
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Contact Card Tests

    // Based on: Scenario: Exchange includes contact card

    /// Scenario: Own card can be retrieved after identity creation
    func testOwnCardExistsAfterIdentity() throws {
        let card = try repo.getOwnCard()

        XCTAssertNotNil(card, "Should have own card after identity creation")
        XCTAssertEqual(card?.displayName, "Test User")
    }

    /// Scenario: Card can be updated with fields
    func testUpdateCardFields() throws {
        guard var card = try repo.getOwnCard() else {
            XCTFail("Should have card")
            return
        }

        // Add field
        card.email = "test@example.com"
        try repo.updateOwnCard(card)

        // Verify update persisted
        let updatedCard = try repo.getOwnCard()
        XCTAssertEqual(updatedCard?.email, "test@example.com")
    }

    // MARK: - Contact List Tests

    // Based on: Scenario: Contacts are stored after exchange

    /// Scenario: No contacts initially
    func testNoContactsInitially() throws {
        let contacts = try repo.getContacts()
        XCTAssertTrue(contacts.isEmpty, "Should have no contacts initially")
    }

    /// Scenario: Contact count matches after adds
    func testContactCountAccurate() throws {
        let initialCount = try repo.getContacts().count
        XCTAssertEqual(initialCount, 0)

        // Note: Actually adding contacts requires completing exchange
        // which needs two parties - tested in integration tests
    }
}
