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
    func testInitBootstrapsWakeupLoop() {
        XCTAssertTrue(
            WakeupService.shared.hasScheduledWakeup,
            "AppViewModel.init must bootstrap the core-owned poll loop"
        )
    }

    /// After a background cancel disarms the loop, `onWakeup` re-arms it —
    /// the exact guarantee the `.active` scenePhase handler depends on.
    func testOnWakeupReArmsAfterBackgroundCancel() {
        WakeupService.shared.cancelPendingWakeup()
        XCTAssertFalse(
            WakeupService.shared.hasScheduledWakeup,
            "background cancel must disarm the loop"
        )

        viewModel.onWakeup()

        XCTAssertTrue(
            WakeupService.shared.hasScheduledWakeup,
            "onWakeup (foreground re-arm) must re-schedule the loop"
        )
    }
}
