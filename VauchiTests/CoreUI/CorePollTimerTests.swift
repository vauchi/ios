// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for AppViewModel's app-level core poll-timer lifecycle.
// Regression guard for the BLE/NFC/cable "Searching… forever" wait bug: a
// peerless bounded-wait exchange must reach its stall budget. The pump drives
// `pollNotifications` on a ~1s cadence across every core screen so the
// engine's BLE_STEP_TIMEOUT_SECS deadline fires; the invalidation listener
// then surfaces `exchange_failed`. iOS counterpart of the Android MainActivity
// app-level pump (`CORE_CADENCE_TICK_INTERVAL_MS`).

@testable import Vauchi
import XCTest

/// Unit tests for `AppViewModel.startCorePollTimer` / `stopCorePollTimer`.
/// Unlike the view-driven multi-stage pump, this pump is started in `init`
/// (active for the whole core-UI session) and self-invalidates on dealloc, so
/// it must be active immediately after construction. Both start and stop are
/// idempotent.
@MainActor
final class CorePollTimerTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Test User")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel.stopCorePollTimer()
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Scenario: the pump is active immediately after `init` — it must drive
    /// the engine on every core screen, not wait for a view to start it.
    func testCorePollTimerActiveAfterInit() {
        XCTAssertTrue(viewModel.hasActiveCorePollTimer, "init starts the app-level core pump")
    }

    /// Scenario: stopping then starting toggles the pump cleanly.
    func testStopThenStartReactivates() {
        viewModel.stopCorePollTimer()
        XCTAssertFalse(viewModel.hasActiveCorePollTimer, "stop deactivates")

        viewModel.startCorePollTimer()
        XCTAssertTrue(viewModel.hasActiveCorePollTimer, "start re-activates")
    }

    /// Scenario: starting an already-running pump does not create a second timer.
    func testStartCorePollTimerIsIdempotent() {
        XCTAssertTrue(viewModel.hasActiveCorePollTimer, "active from init")

        viewModel.startCorePollTimer()
        XCTAssertTrue(viewModel.hasActiveCorePollTimer, "second start is a no-op")
    }

    /// Scenario: stopping twice in a row is safe.
    func testStopCorePollTimerIsIdempotent() {
        viewModel.stopCorePollTimer()
        viewModel.stopCorePollTimer()
        XCTAssertFalse(viewModel.hasActiveCorePollTimer, "stop on inactive stays inactive")
    }

    /// Scenario: repeated start/stop cycles don't leak timers.
    func testStartStopCycleRepeatable() {
        for _ in 0 ..< 5 {
            viewModel.stopCorePollTimer()
            XCTAssertFalse(viewModel.hasActiveCorePollTimer)
            viewModel.startCorePollTimer()
            XCTAssertTrue(viewModel.hasActiveCorePollTimer)
        }
    }
}
