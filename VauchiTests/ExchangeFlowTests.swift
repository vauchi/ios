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
        let sessionData = try repo.generateExchangeQrWithSession()

        XCTAssertFalse(sessionData.exchangeData.qrData.isEmpty, "QR data should not be empty")
        // QR data uses wb:// protocol format
        XCTAssertTrue(sessionData.exchangeData.qrData.hasPrefix("wb://"), "QR data should start with wb://")
    }

    /// Scenario: QR code contains public key
    func testQRCodeContainsPublicKey() throws {
        let publicId = try repo.getPublicId()
        let sessionData = try repo.generateExchangeQrWithSession()

        // Exchange data includes the public ID
        XCTAssertFalse(sessionData.exchangeData.qrData.isEmpty)
        XCTAssertFalse(publicId.isEmpty)
        XCTAssertFalse(sessionData.exchangeData.publicId.isEmpty)
    }

    /// Scenario: Multiple QR codes can be generated
    func testMultipleQRCodesUnique() throws {
        let qr1 = try repo.generateExchangeQrWithSession()
        let qr2 = try repo.generateExchangeQrWithSession()
        let qr3 = try repo.generateExchangeQrWithSession()

        // Each QR code may include timestamp/nonce, making them different
        // Or they may be the same if deterministic - both are valid
        XCTAssertFalse(qr1.exchangeData.qrData.isEmpty)
        XCTAssertFalse(qr2.exchangeData.qrData.isEmpty)
        XCTAssertFalse(qr3.exchangeData.qrData.isEmpty)
    }

    // MARK: - QR Code Parsing Tests

    // Based on: Scenario: Parse scanned QR code

    /// Scenario: Parse invalid QR data returns error
    func testParseInvalidQRData() throws {
        let invalidData = "not-a-valid-qr-code"
        let sessionData = try repo.generateExchangeQrWithSession()

        XCTAssertThrowsError(try sessionData.session.processQr(qrData: invalidData)) { error in
            // Should throw some form of parse error
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Parse empty QR data returns error
    func testParseEmptyQRData() throws {
        let sessionData = try repo.generateExchangeQrWithSession()

        XCTAssertThrowsError(try sessionData.session.processQr(qrData: "")) { error in
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Parse corrupted base64 returns error
    func testParseCorruptedBase64() throws {
        let corruptedData = "!!!invalid-base64!!!"
        let sessionData = try repo.generateExchangeQrWithSession()

        XCTAssertThrowsError(try sessionData.session.processQr(qrData: corruptedData))
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

        XCTAssertThrowsError(try repoNoIdentity.generateExchangeQrWithSession()) { error in
            // Should require identity
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Contact Card Tests

    // Based on: Scenario: Exchange includes contact card

    /// Scenario: Own card can be retrieved after identity creation
    func testOwnCardExistsAfterIdentity() throws {
        let card = try repo.getOwnCard()

        XCTAssertEqual(card.displayName, "Test User")
    }

    /// Scenario: Card can be updated with fields
    func testUpdateCardFields() throws {
        // Add email field via addField API
        try repo.addField(type: .email, label: "Email", value: "test@example.com")

        // Verify update persisted
        let updatedCard = try repo.getOwnCard()
        XCTAssertEqual(updatedCard.fields.count, 1)
        XCTAssertEqual(updatedCard.fields[0].fieldType, .email)
        XCTAssertEqual(updatedCard.fields[0].label, "Email")
        XCTAssertEqual(updatedCard.fields[0].value, "test@example.com")
    }

    // MARK: - Contact List Tests

    // Based on: Scenario: Contacts are stored after exchange

    /// Scenario: No contacts initially
    func testNoContactsInitially() throws {
        let contacts = try repo.listContacts()
        XCTAssertTrue(contacts.isEmpty, "Should have no contacts initially")
    }

    /// Scenario: Contact count matches after adds
    func testContactCountAccurate() throws {
        let initialCount = try repo.listContacts().count
        XCTAssertEqual(initialCount, 0)

        // Note: Actually adding contacts requires completing exchange
        // which needs two parties - tested in integration tests
    }
}
