// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for BackgroundSyncService
// Based on: features/sync_updates.feature - background sync requirements

@testable import Vauchi
import XCTest

final class BackgroundSyncServiceTests: XCTestCase {
    // MARK: - Initialization Tests

    /// Scenario: BackgroundSyncService is a singleton
    func testBackgroundSyncServiceIsSingleton() {
        let service1 = BackgroundSyncService.shared
        let service2 = BackgroundSyncService.shared

        XCTAssertTrue(service1 === service2, "BackgroundSyncService should be a singleton")
    }

    /// Scenario: BackgroundSyncService has correct task identifier
    func testSyncTaskIdentifier() {
        XCTAssertEqual(
            BackgroundSyncService.syncTaskIdentifier,
            "app.vauchi.sync",
            "Task identifier should match expected value"
        )
    }

    // MARK: - Task Outcome Tests (private#958)

    func testAFailedSyncReportsFailureToTheScheduler() async {
        var delivered: [Bool] = []
        let completion = SyncTaskCompletion { delivered.append($0) }

        await BackgroundSyncService.run(handler: { false }, completion: completion)

        XCTAssertEqual(delivered, [false])
    }

    func testASuccessfulSyncReportsSuccessToTheScheduler() async {
        var delivered: [Bool] = []
        let completion = SyncTaskCompletion { delivered.append($0) }

        await BackgroundSyncService.run(handler: { true }, completion: completion)

        XCTAssertEqual(delivered, [true])
    }

    func testAMissingHandlerReportsFailure() async {
        var delivered: [Bool] = []
        let completion = SyncTaskCompletion { delivered.append($0) }

        await BackgroundSyncService.run(handler: nil, completion: completion)

        XCTAssertEqual(delivered, [false])
    }

    /// BGTask must be completed once: iOS can expire it while the sync runs.
    func testExpiryWhileRunningCompletesTheTaskOnlyOnce() async {
        var delivered: [Bool] = []
        let completion = SyncTaskCompletion { delivered.append($0) }

        await BackgroundSyncService.run(
            handler: {
                completion.finish(success: false)
                return true
            },
            completion: completion
        )

        XCTAssertEqual(delivered, [false])
    }

    // MARK: - Sync Handler Tests

    /// Scenario: Sync handler can be set and is retained
    func testSetSyncHandlerRetainsHandler() {
        let service = BackgroundSyncService.shared
        var called = false

        service.setSyncHandler {
            called = true
            return true
        }

        // Handler is stored — we can't invoke it directly (BGTask triggers it),
        // but setting it should not crash and the service should remain usable
        XCTAssertFalse(called, "Handler should not be called until a BGTask fires")
    }

    // Note: registerBackgroundTasks() and scheduleSyncTask() call
    // BGTaskScheduler APIs that throw NSExceptions in simulator/test
    // environments when the task identifier is not in the host app's
    // Info.plist. These are integration-level behaviors that require
    // device testing, not unit tests.
}
