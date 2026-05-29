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
