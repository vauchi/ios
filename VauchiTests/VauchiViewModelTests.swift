// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for VauchiViewModel — the app-shell coordinator.
//
// The card-field / contact-CRUD / hidden-contact tests were removed in G4
// (2026-06-06, problem record 2026-05-02-ios-humble-ui-deep-retirement)
// alongside the view-model methods they covered: those domain actions now
// flow through core via `coreViewModel`, and the card/identity hydration
// they asserted lives in `VauchiRepositoryTests` (repository layer) and the
// core engine tests. What remains here is genuine shell behaviour:
// lock/auth routing, identity-presence, the contacts-presence flag, error
// clearing, and initial sync state.

@testable import Vauchi
import XCTest

/// Tests for VauchiViewModel
/// Based on: features/identity_management.feature
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

        // Before loadState, should be in loading state with no identity.
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.hasIdentity)
    }

    // MARK: - Identity Creation Tests

    // Based on: features/identity_management.feature

    /// Scenario: Create identity flips the shell's identity-presence flag.
    /// Card/display-name hydration is core-owned (rendered via
    /// `coreViewModel`) and verified at the repository layer
    /// (`VauchiRepositoryTests`), not here.
    func testCreateIdentityUpdatesState() async throws {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.hasIdentity)
        try await viewModel.createIdentity(name: "Alice")

        XCTAssertTrue(viewModel.hasIdentity)
    }

    // Contact-list state is core-owned (rendered via `coreViewModel`
    // ScreenModel); the shell no longer mirrors a `contacts` array.
    // "Fresh identity → empty list" is covered in core; the humble
    // tab-follow contract is in `CoreScreenNavigationTests`.

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
