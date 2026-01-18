// NetworkMonitorTests.swift
// Tests for NetworkMonitor service
// Based on: features/sync_updates.feature - network connectivity requirements

import XCTest
@testable import Vauchi

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
        // Verify all connection types exist
        let wifi = NetworkMonitor.ConnectionType.wifi
        let cellular = NetworkMonitor.ConnectionType.cellular
        let wired = NetworkMonitor.ConnectionType.wired
        let unknown = NetworkMonitor.ConnectionType.unknown

        XCTAssertNotNil(wifi)
        XCTAssertNotNil(cellular)
        XCTAssertNotNil(wired)
        XCTAssertNotNil(unknown)
    }

    // MARK: - Published Properties Tests

    /// Scenario: isConnected is published for observation
    func testIsConnectedIsPublished() {
        let monitor = NetworkMonitor.shared

        // Access the published property - should not crash
        let _ = monitor.$isConnected
    }

    /// Scenario: connectionType is published for observation
    func testConnectionTypeIsPublished() {
        let monitor = NetworkMonitor.shared

        // Access the published property - should not crash
        let _ = monitor.$connectionType
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
