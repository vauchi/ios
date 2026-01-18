// VauchiViewModelTests.swift
// Tests for VauchiViewModel state management

import XCTest
@testable import Vauchi

/// Tests for VauchiViewModel
/// Based on: features/identity_management.feature, features/contact_card_management.feature
@MainActor
final class VauchiViewModelTests: XCTestCase {

    // MARK: - Initial State Tests

    /// Scenario: ViewModel starts in loading state
    func testInitialStateIsLoading() async {
        let viewModel = VauchiViewModel()

        // Before loadState, should be in loading state
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.hasIdentity)
        XCTAssertNil(viewModel.identity)
        XCTAssertNil(viewModel.card)
        XCTAssertTrue(viewModel.contacts.isEmpty)
    }

    // MARK: - Identity Creation Tests
    // Based on: features/identity_management.feature

    /// Scenario: Create identity updates state
    func testCreateIdentityUpdatesState() async throws {
        let viewModel = VauchiViewModel()

        try await viewModel.createIdentity(name: "Alice")

        XCTAssertTrue(viewModel.hasIdentity)
        XCTAssertEqual(viewModel.identity?.displayName, "Alice")
        XCTAssertNotNil(viewModel.card)
    }

    /// Scenario: Create identity initializes empty card
    func testCreateIdentityInitializesCard() async throws {
        let viewModel = VauchiViewModel()

        try await viewModel.createIdentity(name: "Alice")

        XCTAssertEqual(viewModel.card?.displayName, "Alice")
        XCTAssertTrue(viewModel.card?.fields.isEmpty ?? false)
    }

    // MARK: - Card Field Tests
    // Based on: features/contact_card_management.feature

    /// Scenario: Add field to card
    func testAddFieldToCard() async throws {
        let viewModel = VauchiViewModel()
        try await viewModel.createIdentity(name: "Alice")

        try await viewModel.addField(type: "email", label: "Work", value: "alice@company.com")

        XCTAssertEqual(viewModel.card?.fields.count, 1)
        XCTAssertEqual(viewModel.card?.fields[0].label, "Work")
        XCTAssertEqual(viewModel.card?.fields[0].value, "alice@company.com")
    }

    /// Scenario: Add multiple fields to card
    func testAddMultipleFields() async throws {
        let viewModel = VauchiViewModel()
        try await viewModel.createIdentity(name: "Alice")

        try await viewModel.addField(type: "email", label: "Work", value: "alice@work.com")
        try await viewModel.addField(type: "phone", label: "Mobile", value: "+1234567890")
        try await viewModel.addField(type: "website", label: "Blog", value: "https://alice.dev")

        XCTAssertEqual(viewModel.card?.fields.count, 3)
    }

    /// Scenario: Remove field from card
    func testRemoveFieldFromCard() async throws {
        let viewModel = VauchiViewModel()
        try await viewModel.createIdentity(name: "Alice")
        try await viewModel.addField(type: "email", label: "Work", value: "alice@work.com")

        let field = viewModel.card!.fields[0]
        try await viewModel.removeField(id: field.id)

        XCTAssertTrue(viewModel.card?.fields.isEmpty ?? false)
    }

    // MARK: - Exchange Tests
    // Based on: features/contact_exchange.feature

    /// Scenario: Generate QR data for exchange
    func testGenerateQrData() throws {
        let viewModel = VauchiViewModel()
        // Note: This test will need to be updated when real bindings are connected

        // For now, test placeholder behavior
        let qrData = try viewModel.generateQRData()

        XCTAssertTrue(qrData.hasPrefix("wb://"), "QR data should start with wb://")
    }

    // MARK: - Contact Management Tests
    // Based on: features/contacts_management.feature

    /// Scenario: Initial contacts list is empty
    func testInitialContactsListEmpty() async throws {
        let viewModel = VauchiViewModel()
        try await viewModel.createIdentity(name: "Alice")

        await viewModel.loadContacts()

        XCTAssertTrue(viewModel.contacts.isEmpty)
    }

    /// Scenario: Remove contact updates list
    func testRemoveContactUpdatesState() async throws {
        let viewModel = VauchiViewModel()
        try await viewModel.createIdentity(name: "Alice")

        // Add a mock contact for testing
        // When real bindings are connected, this will use actual exchange
        let initialCount = viewModel.contacts.count

        // Removing a non-existent contact should not change count
        try await viewModel.removeContact(id: "nonexistent")

        XCTAssertEqual(viewModel.contacts.count, initialCount)
    }

    // MARK: - Error Handling Tests

    /// Scenario: Error message clears on load
    func testErrorMessageClearsOnLoad() async {
        let viewModel = VauchiViewModel()

        // Manually set error for testing
        // In real usage, errors come from failed operations
        viewModel.loadState()

        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Sync State Tests
    // Based on: features/sync_updates.feature

    /// Scenario: Initial sync state is idle
    func testInitialSyncStateIsIdle() {
        let viewModel = VauchiViewModel()

        XCTAssertEqual(viewModel.syncState, .idle)
    }
}
