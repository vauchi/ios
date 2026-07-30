// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Phase 2A (core-gui-architecture-alignment): AppViewModel wires a
// PlatformEventListener on init so that async core events (background
// sync, delivery receipts, device link) refresh the rendered screen
// without requiring a user action.
//
// The callback may fire on any thread; the implementation must marshal
// to the main queue before touching the engine (UniFFI Mutex deadlock).

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class PlatformEventListenerTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Listener Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Scenario: a PlatformEventListener is attached after construction.
    /// If this fails, async core events never reach the UI and screens
    /// become stale until the user taps something.
    func testEventListenerIsRegisteredOnInit() {
        XCTAssertTrue(
            viewModel.hasEventListener,
            "AppViewModel must register a PlatformEventListener with the engine " +
                "so core-side invalidations reach the UI without a user action"
        )
    }

    /// Scenario: onScreensInvalidated dispatches to the main queue and
    /// reloads the generic presentation. We simulate the core callback by
    /// invoking the listener directly, then wait for the main-queue hop.
    func testOnScreensInvalidatedReloadsPresentation() async throws {
        let listener = try XCTUnwrap(
            viewModel.eventListenerForTesting,
            "event listener must be accessible to tests"
        )
        let surfaceIDBefore = viewModel.presentationState.activeSurfaceID

        // Off-main invocation mirrors how core dispatches the callback.
        await Task.detached {
            listener.onScreensInvalidated(screenIds: ["home"])
        }.value

        // Allow the main-queue hop the implementation performs.
        try await Task.sleep(nanoseconds: 100_000_000)

        let activeSurfaceID = try XCTUnwrap(
            viewModel.presentationState.activeSurfaceID,
            "reload must yield an active generic surface"
        )
        if let before = surfaceIDBefore {
            XCTAssertEqual(
                activeSurfaceID,
                before,
                "reloading unchanged Core state must retain the active surface id"
            )
        }
    }
}
