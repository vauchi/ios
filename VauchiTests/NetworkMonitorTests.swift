// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NetworkMonitorTests.swift
// Tests for NetworkMonitor service
// Based on: features/sync_updates.feature - network connectivity requirements

@testable import Vauchi
import XCTest

final class NetworkMonitorTests: XCTestCase {
    // MARK: - Initialization Tests

    /// Scenario: NetworkMonitor is a singleton
    func testNetworkMonitorIsSingleton() {
        let monitor1 = NetworkMonitor.shared
        let monitor2 = NetworkMonitor.shared

        XCTAssertTrue(monitor1 === monitor2, "NetworkMonitor should be a singleton")
    }

    /// Scenario: NetworkMonitor has initial state
    func testNetworkMonitorHasInitialState() {
        let monitor = NetworkMonitor.shared

        // Connection type should be one of the valid types
        let validTypes: [NetworkMonitor.ConnectionType] = [.wifi, .cellular, .wired, .unknown]
        XCTAssertTrue(validTypes.contains(monitor.connectionType), "Should have valid connection type")
    }

    // MARK: - Connection Type Tests

    /// Scenario: ConnectionType enum has all expected cases
    func testConnectionTypeHasAllCases() {
        // Each case must be distinct — relying on Set equality catches an
        // accidental aliasing collapse (e.g. wired = wifi) that a plain
        // existence check would silently miss.
        let allCases: Set<NetworkMonitor.ConnectionType> = [
            .wifi, .cellular, .wired, .unknown,
        ]

        XCTAssertEqual(allCases.count, 4,
                       "ConnectionType must expose 4 distinct cases (wifi, cellular, wired, unknown)")
    }

    // MARK: - Published Properties Tests

    /// Scenario: isConnected is published for observation
    func testIsConnectedIsPublished() {
        let monitor = NetworkMonitor.shared

        // Access the published property - should not crash
        _ = monitor.$isConnected
    }

    /// Scenario: connectionType is published for observation
    func testConnectionTypeIsPublished() {
        let monitor = NetworkMonitor.shared

        // Access the published property - should not crash
        _ = monitor.$connectionType
    }

    // MARK: - Start/Stop Tests

    /// Scenario: NetworkMonitor can be started and stopped
    func testNetworkMonitorCanStartAndStop() {
        let monitor = NetworkMonitor.shared

        // Should not crash
        monitor.start()
        monitor.stop()
    }
}
