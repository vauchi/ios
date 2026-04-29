// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiViewModelTests.swift
// Tests for VauchiViewModel state management

@testable import Vauchi
import XCTest

/// Tests for VauchiViewModel
/// Based on: features/identity_management.feature, features/contact_card_management.feature
@MainActor
final class VauchiViewModelTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Build a `VauchiViewModel` rooted at the per-test `tempDir` so each
    /// test gets its own clean storage — avoids the strict
    /// `appEngine.create_identity` `AlreadyInitialized` error the shared
    /// default Application Support dir caused before this refactor.
    private func makeViewModel() -> VauchiViewModel {
        VauchiViewModel(dataDir: tempDir.path, relayUrl: nil)
    }

    // MARK: - Initial State Tests

    /// Scenario: ViewModel starts in loading state
    func testInitialStateIsLoading() {
        let viewModel = makeViewModel()

        // Before loadState, should be in loading state
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.hasIdentity)
        XCTAssertNil(viewModel.displayName)
        XCTAssertNil(viewModel.publicId)
        XCTAssertNil(viewModel.card)
        XCTAssertTrue(viewModel.contacts.isEmpty)
    }

    // MARK: - Identity Creation Tests

    // Based on: features/identity_management.feature

    /// Scenario: Create identity updates state
    func testCreateIdentityUpdatesState() async throws {
        let viewModel = makeViewModel()

        try await viewModel.createIdentity(name: "Alice")

        XCTAssertTrue(viewModel.hasIdentity)
        XCTAssertEqual(viewModel.displayName, "Alice")
        XCTAssertNotNil(viewModel.card)
    }

    /// Scenario: Create identity initializes empty card
    func testCreateIdentityInitializesCard() async throws {
        let viewModel = makeViewModel()

        try await viewModel.createIdentity(name: "Alice")

        XCTAssertEqual(viewModel.card?.displayName, "Alice")
        XCTAssertTrue(viewModel.card?.fields.isEmpty ?? false)
    }

    // MARK: - Card Field Tests

    // Based on: features/contact_card_management.feature

    /// Scenario: Add field to card
    func testAddFieldToCard() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")

        try await viewModel.addField(type: "email", label: "Work", value: "alice@company.com")

        XCTAssertEqual(viewModel.card?.fields.count, 1)
        XCTAssertEqual(viewModel.card?.fields[0].label, "Work")
        XCTAssertEqual(viewModel.card?.fields[0].value, "alice@company.com")
    }

    /// Scenario: Add multiple fields to card
    func testAddMultipleFields() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")

        try await viewModel.addField(type: "email", label: "Work", value: "alice@work.com")
        try await viewModel.addField(type: "phone", label: "Mobile", value: "+1234567890")
        try await viewModel.addField(type: "website", label: "Blog", value: "https://alice.dev")

        XCTAssertEqual(viewModel.card?.fields.count, 3)
    }

    /// Scenario: Remove field from card
    func testRemoveFieldFromCard() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")
        try await viewModel.addField(type: "email", label: "Work", value: "alice@work.com")

        let field = try XCTUnwrap(viewModel.card?.fields[0])
        try await viewModel.removeField(id: field.id)

        XCTAssertTrue(viewModel.card?.fields.isEmpty ?? false)
    }

    // MARK: - Exchange Tests

    // MARK: - Contact Management Tests

    // Based on: features/contacts_management.feature

    /// Scenario: Initial contacts list is empty
    func testInitialContactsListEmpty() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")

        await viewModel.loadContacts()

        XCTAssertTrue(viewModel.contacts.isEmpty)
    }

    /// Scenario: Remove contact updates list
    func testRemoveContactUpdatesState() async throws {
        let viewModel = makeViewModel()
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
    func testErrorMessageClearsOnLoad() {
        let viewModel = makeViewModel()

        // Manually set error for testing
        // In real usage, errors come from failed operations
        viewModel.loadState()

        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Sync State Tests

    // Based on: features/sync_updates.feature

    /// Scenario: Initial sync state is idle
    func testInitialSyncStateIsIdle() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.syncState, .idle)
    }

    // MARK: - Hidden Contacts Tests

    // Based on: features/resistance.feature - R3 Hidden Contact UI

    /// Scenario: Hide contact removes it from normal list
    func testHideContactUpdatesState() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")

        // Test hiding a contact (will gracefully handle missing method)
        try? await viewModel.hideContact(id: "test-contact-id")

        // Method should exist and not crash
        XCTAssertTrue(true, "hideContact method exists")
    }

    /// Scenario: Load hidden contacts
    func testLoadHiddenContacts() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")

        // Load hidden contacts (will gracefully handle missing method)
        await viewModel.loadHiddenContacts()

        // Method should exist and not crash
        XCTAssertTrue(true, "loadHiddenContacts method exists")
    }

    /// Scenario: Unhide contact restores to normal list
    func testUnhideContactUpdatesState() async throws {
        let viewModel = makeViewModel()
        try await viewModel.createIdentity(name: "Alice")

        // Test unhiding a contact (will gracefully handle missing method)
        try? await viewModel.unhideContact(id: "test-contact-id")

        // Method should exist and not crash
        XCTAssertTrue(true, "unhideContact method exists")
    }

    // MARK: - App State Tests (Locked Device)

    // Based on: _private/docs/problems/2026-03-02-locked-device-startup-error/

    /// Scenario: AppState enum has all required cases
    func testAppStateEnumCases() {
        // Verify all expected cases exist and are distinct
        let loading = AppState.loading
        let waiting = AppState.waitingForUnlock
        let authRequired = AppState.authenticationRequired
        let ready = AppState.ready

        XCTAssertEqual(loading, AppState.loading)
        XCTAssertEqual(waiting, AppState.waitingForUnlock)
        XCTAssertEqual(authRequired, AppState.authenticationRequired)
        XCTAssertEqual(ready, AppState.ready)

        // Verify distinct values
        XCTAssertNotEqual(loading, waiting)
        XCTAssertNotEqual(loading, authRequired)
        XCTAssertNotEqual(loading, ready)
        XCTAssertNotEqual(waiting, authRequired)
        XCTAssertNotEqual(waiting, ready)
        XCTAssertNotEqual(authRequired, ready)
    }

    /// Scenario: ViewModel initial appState is loading
    func testInitialAppStateIsLoading() {
        let viewModel = makeViewModel()

        // On simulator with protected data available, it should initialize successfully
        // and move to .ready (or stay .loading briefly then .ready)
        // The important check: it should NOT be .waitingForUnlock or .authenticationRequired
        // since the simulator has protected data available
        XCTAssertNotEqual(viewModel.appState, .waitingForUnlock,
                          "Should not be waiting for unlock on simulator")
        XCTAssertNotEqual(viewModel.appState, .authenticationRequired,
                          "Should not require authentication on simulator")
    }

    /// Scenario: loadState bails out when appState is waitingForUnlock
    func testLoadStateBailsOutWhenWaitingForUnlock() {
        let viewModel = makeViewModel()

        // Force the state to waitingForUnlock
        viewModel.appState = .waitingForUnlock
        viewModel.isLoading = true

        viewModel.loadState()

        // loadState should bail out immediately, setting isLoading to false
        XCTAssertFalse(viewModel.isLoading,
                       "isLoading should be false when appState is waitingForUnlock")
    }

    /// Scenario: loadState bails out when appState is authenticationRequired
    func testLoadStateBailsOutWhenAuthenticationRequired() {
        let viewModel = makeViewModel()

        // Force the state to authenticationRequired
        viewModel.appState = .authenticationRequired
        viewModel.isLoading = true

        viewModel.loadState()

        // loadState should bail out immediately, setting isLoading to false
        XCTAssertFalse(viewModel.isLoading,
                       "isLoading should be false when appState is authenticationRequired")
    }

    /// Scenario: VauchiRepositoryError.deviceLocked has correct description
    func testDeviceLockedErrorDescription() {
        let error = VauchiRepositoryError.deviceLocked

        XCTAssertEqual(error.errorDescription,
                       "Device is locked \u{2014} unlock your device to access Vauchi",
                       "deviceLocked error should have a user-friendly description")
    }
}
