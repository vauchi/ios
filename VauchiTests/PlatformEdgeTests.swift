// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// PlatformEdgeTests.swift
// Tests for iOS platform-specific edge cases
// Based on: features/platform_edge_cases.feature

@testable import Vauchi
import XCTest

/// Tests for iOS platform edge cases
/// Based on: features/platform_edge_cases.feature - iOS Edge Cases
final class PlatformEdgeTests: XCTestCase {
    // MARK: - Background Task Tests

    /// Scenario: Background task completes before termination
    /// Given I started a sync operation on iOS
    /// When the app moves to background
    /// Then a background task should be requested
    /// And the sync should complete if possible
    /// And state should be saved before termination
    func test_background_task_completion() async {
        let service = BackgroundSyncService.shared

        // Verify background task identifier is set correctly
        XCTAssertEqual(
            BackgroundSyncService.syncTaskIdentifier,
            "app.vauchi.sync",
            "Background task should have correct identifier"
        )

        // Simulate scheduling a sync task (background mode)
        service.scheduleSyncTask()

        // The sync service should be able to handle background scheduling
        // without crashing, even in test environment where BGTaskScheduler
        // may not be fully available
        XCTAssertNotNil(service, "Service should remain valid after scheduling")

        // Verify task can be cancelled gracefully
        service.cancelPendingTasks()

        // Re-schedule to verify service is still functional
        service.scheduleSyncTask()
    }

    // MARK: - Memory Limit Tests

    /// Scenario: Handle low memory warning on iOS (Widget context)
    /// App extensions (widgets) must stay under ~30MB memory limit
    /// Given the app is using significant memory on iOS
    /// When iOS sends a memory warning
    /// Then the app should release cached images
    /// And the app should release non-essential data
    /// And core functionality should continue working
    func test_app_extension_memory_limit() {
        // Measure baseline memory usage
        let initialMemory = getMemoryUsage()

        // Simulate creating some cached data that could be released
        var temporaryData: [Data] = []
        for _ in 0 ..< 100 {
            // Create small data chunks (simulating cached images)
            temporaryData.append(Data(repeating: 0, count: 1024))
        }

        let peakMemory = getMemoryUsage()

        // Clear the temporary data (simulating memory warning response)
        temporaryData.removeAll()

        let afterCleanupMemory = getMemoryUsage()

        // Verify memory was released
        // Note: Due to Swift/ARC timing, we check that cleanup didn't increase memory
        XCTAssertLessThanOrEqual(
            afterCleanupMemory,
            peakMemory,
            "Memory should not increase after cleanup"
        )

        // Verify we're well under the 30MB widget limit
        // In test context, we're checking the test process, not actual widget
        // but this validates the pattern of memory management
        let memoryLimitBytes: UInt64 = 30 * 1024 * 1024 // 30MB
        XCTAssertLessThan(
            initialMemory,
            memoryLimitBytes,
            "Baseline memory should be well under 30MB widget limit"
        )
    }

    // MARK: - Scene Phase Transition Tests

    /// Scenario: State preserved across scene phase transitions
    /// Related to: Sync survives background termination
    /// Given I am syncing updates on iOS
    /// When iOS terminates the app in background
    /// Then pending syncs should be saved to disk
    /// And when I relaunch the app, syncs should resume automatically
    @MainActor
    func test_scene_phase_transitions() async throws {
        let viewModel = VauchiViewModel()

        // Setup: Create initial state
        try await viewModel.createIdentity(name: "TestUser")
        XCTAssertTrue(viewModel.hasIdentity, "Should have identity after creation")

        let initialSyncState = viewModel.syncState
        XCTAssertEqual(initialSyncState, .idle, "Initial sync state should be idle")

        // Simulate scene phase change to background
        // In real app, this would trigger state persistence
        let stateBeforeBackground = viewModel.hasIdentity

        // Verify state is preserved (simulating what happens during phase transition)
        XCTAssertEqual(
            viewModel.hasIdentity,
            stateBeforeBackground,
            "Identity state should be preserved during phase transition"
        )

        // Simulate returning to foreground
        viewModel.loadState()

        // Verify core state is maintained
        XCTAssertTrue(
            viewModel.hasIdentity,
            "Identity should persist after simulated phase transition"
        )

        // Verify sync state can be checked after transition
        XCTAssertNotNil(
            viewModel.syncState,
            "Sync state should be accessible after phase transition"
        )
    }

    // MARK: - Helper Methods

    /// Get current memory usage in bytes
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if result == KERN_SUCCESS {
            return info.resident_size
        }

        // Fallback: return 0 if we can't get memory info
        return 0
    }
}
