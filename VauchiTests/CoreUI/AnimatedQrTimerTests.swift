// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AnimatedQrTimerTests.swift
// Tests for AppViewModel QR frame timer lifecycle.
// Based on: features/contact_exchange.feature — animated QR frames.

@testable import Vauchi
import XCTest

/// Unit tests for `AppViewModel.startQrFrameTimer` / `stopQrFrameTimer`.
/// The view layer toggles these on `.onAppear` / `.onChange` / `.onDisappear`
/// of the ShowQr screen; both start and stop must be idempotent because the
/// view may hand the same transition (e.g. scene restoration before the
/// first `.onChange` fires) to both lifecycle hooks.
@MainActor
final class AnimatedQrTimerTests: XCTestCase {
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
        viewModel.stopQrFrameTimer()
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Scenario: starting the timer twice does not create a second timer.
    func testStartQrFrameTimerIsIdempotent() {
        XCTAssertFalse(viewModel.hasActiveQrFrameTimer, "starts inactive")

        viewModel.startQrFrameTimer()
        XCTAssertTrue(viewModel.hasActiveQrFrameTimer, "first start activates")

        viewModel.startQrFrameTimer()
        XCTAssertTrue(viewModel.hasActiveQrFrameTimer, "second start is a no-op")
    }

    /// Scenario: stopping an inactive timer is a no-op.
    func testStopQrFrameTimerOnInactiveIsSafe() {
        XCTAssertFalse(viewModel.hasActiveQrFrameTimer)

        viewModel.stopQrFrameTimer()
        XCTAssertFalse(viewModel.hasActiveQrFrameTimer, "stop on inactive stays inactive")
    }

    /// Scenario: start then stop clears the timer.
    func testStartThenStopDeactivates() {
        viewModel.startQrFrameTimer()
        XCTAssertTrue(viewModel.hasActiveQrFrameTimer)

        viewModel.stopQrFrameTimer()
        XCTAssertFalse(viewModel.hasActiveQrFrameTimer)
    }

    /// Scenario: stop twice in a row is safe.
    func testStopTwiceIsIdempotent() {
        viewModel.startQrFrameTimer()
        viewModel.stopQrFrameTimer()
        viewModel.stopQrFrameTimer()
        XCTAssertFalse(viewModel.hasActiveQrFrameTimer)
    }

    /// Scenario: start/stop cycle can be repeated without leaking timers.
    func testStartStopCycleRepeatable() {
        for _ in 0 ..< 5 {
            viewModel.startQrFrameTimer()
            XCTAssertTrue(viewModel.hasActiveQrFrameTimer)
            viewModel.stopQrFrameTimer()
            XCTAssertFalse(viewModel.hasActiveQrFrameTimer)
        }
    }
}
