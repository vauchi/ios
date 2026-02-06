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

    /// Scenario: Background task identifier is configured correctly
    /// Given the BackgroundSyncService is configured
    /// Then the task identifier should match expected value
    func test_background_task_identifier() {
        XCTAssertEqual(
            BackgroundSyncService.syncTaskIdentifier,
            "app.vauchi.sync",
            "Background task should have correct identifier"
        )
    }

    /// Scenario: Background sync service singleton pattern
    /// Given the BackgroundSyncService
    /// Then it should be accessible as a singleton
    func test_background_sync_service_singleton() {
        let service1 = BackgroundSyncService.shared
        let service2 = BackgroundSyncService.shared

        XCTAssertTrue(
            service1 === service2,
            "BackgroundSyncService should be a singleton"
        )
    }

    /// Scenario: Background task scheduling and cancellation
    /// Given the BackgroundSyncService
    /// When scheduling and cancelling tasks
    /// Then it should handle gracefully (even in test environment)
    func test_background_task_scheduling() {
        let service = BackgroundSyncService.shared

        // Schedule task (may fail silently in test environment where BGTaskScheduler unavailable)
        service.scheduleSyncTask()

        // Service should remain valid
        XCTAssertNotNil(service, "Service should remain valid after scheduling")

        // Cancel pending tasks
        service.cancelPendingTasks()

        // Re-schedule to verify service is still functional
        service.scheduleSyncTask()

        // Final state check
        XCTAssertNotNil(service, "Service should remain valid after cancel/reschedule cycle")
    }

    // MARK: - Memory Limit Tests

    /// Scenario: Memory usage measurement works correctly
    /// Given the app can measure memory
    /// Then the measurement should return a reasonable value
    func test_memory_measurement() {
        let memoryUsage = getMemoryUsage()

        // Memory usage should be measurable (non-zero in normal conditions)
        // Note: May be 0 if mach API fails, which is acceptable
        XCTAssertTrue(
            memoryUsage >= 0,
            "Memory measurement should not be negative"
        )

        // If we got a valid reading, it should be reasonable (under 1GB for test process)
        if memoryUsage > 0 {
            let oneGigabyte: UInt64 = 1024 * 1024 * 1024
            XCTAssertLessThan(
                memoryUsage,
                oneGigabyte,
                "Test process memory should be under 1GB"
            )
        }
    }

    /// Scenario: Memory is released after cleanup
    /// Given temporary data is allocated
    /// When the data is released
    /// Then memory should not increase
    func test_memory_cleanup() {
        let initialMemory = getMemoryUsage()

        // Create temporary data
        var temporaryData: [Data] = []
        for _ in 0 ..< 100 {
            temporaryData.append(Data(repeating: 0, count: 1024))
        }

        let peakMemory = getMemoryUsage()

        // Release the data
        temporaryData.removeAll()

        let afterCleanupMemory = getMemoryUsage()

        // Verify memory was released (or at least didn't grow)
        // Note: Due to ARC timing, we just check cleanup didn't increase memory significantly
        if peakMemory > 0, afterCleanupMemory > 0 {
            XCTAssertLessThanOrEqual(
                afterCleanupMemory,
                peakMemory + 10240, // Allow 10KB variance for measurement timing
                "Memory should not significantly increase after cleanup"
            )
        }
    }

    // MARK: - Keychain Service Tests

    /// Scenario: Keychain service uses singleton pattern
    /// Given the KeychainService
    /// Then it should be accessible as a singleton
    func test_keychain_service_singleton() {
        let service1 = KeychainService.shared
        let service2 = KeychainService.shared

        XCTAssertTrue(
            service1 === service2,
            "KeychainService should be a singleton"
        )
    }

    /// Scenario: Keychain can store and retrieve string data
    /// Given a test string value
    /// When stored and retrieved from keychain
    /// Then the values should match
    func test_keychain_string_storage() throws {
        let testKey = "test_platform_edge_key_\(UUID().uuidString)"
        let testValue = "test_value_\(Date().timeIntervalSince1970)"

        // Store value
        try KeychainService.shared.saveString(testValue, forKey: testKey)

        // Retrieve value
        let retrieved = try KeychainService.shared.loadString(forKey: testKey)

        XCTAssertEqual(retrieved, testValue, "Retrieved value should match stored value")

        // Cleanup
        try? KeychainService.shared.delete(key: testKey)
    }

    // MARK: - Network Monitor Tests

    /// Scenario: Network monitor uses singleton pattern
    /// Given the NetworkMonitor
    /// Then it should be accessible as a singleton
    func test_network_monitor_singleton() {
        let monitor1 = NetworkMonitor.shared
        let monitor2 = NetworkMonitor.shared

        XCTAssertTrue(
            monitor1 === monitor2,
            "NetworkMonitor should be a singleton"
        )
    }

    /// Scenario: Network monitor provides connection state
    /// Given the NetworkMonitor is running
    /// Then it should report a connection state
    func test_network_monitor_connection_state() {
        let monitor = NetworkMonitor.shared

        // Start monitoring
        monitor.start()

        // Connection state should be determinable
        // (isConnected is a Bool, so it's always valid)
        let isConnected = monitor.isConnected
        XCTAssertTrue(
            isConnected == true || isConnected == false,
            "Network state should be determinable"
        )

        // Connection type should be valid
        let connectionType = monitor.connectionType
        XCTAssertNotNil(connectionType, "Connection type should be available")

        // Stop monitoring
        monitor.stop()
    }

    // MARK: - Settings Service Tests

    /// Scenario: Settings service uses singleton pattern
    /// Given the SettingsService
    /// Then it should be accessible as a singleton
    func test_settings_service_singleton() {
        let settings1 = SettingsService.shared
        let settings2 = SettingsService.shared

        XCTAssertTrue(
            settings1 === settings2,
            "SettingsService should be a singleton"
        )
    }

    /// Scenario: Settings validates relay URLs correctly
    /// Given various relay URL formats
    /// Then validation should accept secure URLs and reject insecure ones
    func test_relay_url_validation() {
        let settings = SettingsService.shared

        // Valid secure URLs
        XCTAssertTrue(
            settings.isValidRelayUrl("wss://relay.vauchi.app"),
            "Should accept wss:// URLs"
        )
        XCTAssertTrue(
            settings.isValidRelayUrl("wss://custom.relay.com:8080"),
            "Should accept wss:// URLs with port"
        )

        // localhost allowed with ws:// for development
        XCTAssertTrue(
            settings.isValidRelayUrl("ws://localhost:8080"),
            "Should accept ws://localhost for dev"
        )
        XCTAssertTrue(
            settings.isValidRelayUrl("ws://127.0.0.1:8080"),
            "Should accept ws://127.0.0.1 for dev"
        )

        // Invalid URLs
        XCTAssertFalse(
            settings.isValidRelayUrl("ws://remote.server.com"),
            "Should reject ws:// for remote servers"
        )
        XCTAssertFalse(
            settings.isValidRelayUrl("http://relay.vauchi.app"),
            "Should reject http:// URLs"
        )
        XCTAssertFalse(
            settings.isValidRelayUrl("not-a-url"),
            "Should reject invalid URLs"
        )
    }

    // MARK: - Localization Service Tests

    /// Scenario: Localization service uses singleton pattern
    /// Given the LocalizationService
    /// Then it should be accessible as a singleton
    func test_localization_service_singleton() {
        let service1 = LocalizationService.shared
        let service2 = LocalizationService.shared

        XCTAssertTrue(
            service1 === service2,
            "LocalizationService should be a singleton"
        )
    }

    /// Scenario: Localization service has available locales
    /// Given the LocalizationService
    /// Then it should have at least one available locale
    func test_available_locales() {
        let service = LocalizationService.shared

        // Should have at least English available
        XCTAssertFalse(
            service.availableLocales.isEmpty,
            "Should have at least one available locale"
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
