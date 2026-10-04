// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import VauchiPlatform
import XCTest

/// F2 (ADR-044 Am2a): the core-owned foreground poll loop must be
/// bootstrapped at `AppViewModel` init and re-armed via `onWakeup`.
///
/// Core emits `Command::ScheduleWakeup` *only* from `on_wakeup`, and the
/// `WakeupService` timer arms *only* from that command — so without the init
/// kick the loop never starts, and the `.active` scenePhase re-arm (which the
/// `VauchiApp` lifecycle handler performs) relies on the same `onWakeup` path.
/// These tests drive that integration through a real engine.
@MainActor
final class WakeupBootstrapTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        WakeupService.shared.cancelPendingWakeup()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Wakeup Bootstrap Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        WakeupService.shared.cancelPendingWakeup()
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Constructing the view model arms the loop: `init` calls `onWakeup`,
    /// core emits the first `ScheduleWakeup`, and the shell schedules it.
    /// Without the init kick the timer would never arm.
    func testInitBootstrapsWakeupLoop() async {
        await viewModel.drainEngineQueue()
        XCTAssertTrue(
            WakeupService.shared.hasScheduledWakeup,
            "AppViewModel.init must bootstrap the core-owned poll loop"
        )
    }

    /// After a background cancel disarms the loop, `onWakeup` re-arms it —
    /// the exact guarantee the `.active` scenePhase handler depends on.
    func testOnWakeupReArmsAfterBackgroundCancel() async {
        await viewModel.drainEngineQueue()
        WakeupService.shared.cancelPendingWakeup()
        XCTAssertFalse(
            WakeupService.shared.hasScheduledWakeup,
            "background cancel must disarm the loop"
        )

        viewModel.onWakeup()
        await viewModel.drainEngineQueue()

        XCTAssertTrue(
            WakeupService.shared.hasScheduledWakeup,
            "onWakeup (foreground re-arm) must re-schedule the loop"
        )
    }

    /// A wakeup takes its turn on the engine queue instead of calling the
    /// engine on the main thread, where it would wait out a BLE burst holding
    /// the engine mutex (vauchi/private#313). While the queue is busy the
    /// wakeup has not run; once the queue drains, it has.
    func testOnWakeupWaitsItsTurnOnTheEngineQueue() async {
        await viewModel.drainEngineQueue()
        WakeupService.shared.cancelPendingWakeup()
        let busy = viewModel.blockEngineQueue()

        viewModel.onWakeup()

        XCTAssertFalse(
            WakeupService.shared.hasScheduledWakeup,
            "onWakeup ran on the main thread instead of queueing behind engine work"
        )
        busy.signal()
        await viewModel.drainEngineQueue()
        XCTAssertTrue(
            WakeupService.shared.hasScheduledWakeup,
            "the queued wakeup must still run once the engine queue is free"
        )
    }
}

extension AppViewModel {
    /// Holds `engineQueue` until the returned semaphore is signalled, standing
    /// in for a long engine call such as a BLE burst.
    func blockEngineQueue() -> DispatchSemaphore {
        let release = DispatchSemaphore(value: 0)
        engineQueue.async { release.wait() }
        return release
    }

    /// Returns once everything queued on `engineQueue` before the call has
    /// run, together with the main-queue hop each item makes afterwards.
    func drainEngineQueue() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            engineQueue.async {
                DispatchQueue.main.async { done.resume() }
            }
        }
    }
}
