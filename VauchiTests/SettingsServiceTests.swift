// SettingsServiceTests.swift
// Tests for SettingsService

import XCTest
@testable import Vauchi

/// Tests for SettingsService
final class SettingsServiceTests: XCTestCase {

    var testDefaults: UserDefaults!
    var service: SettingsService!

    override func setUpWithError() throws {
        // Create a separate UserDefaults suite for testing
        let suiteName = "VauchiSettingsTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        service = SettingsService(defaults: testDefaults)
    }

    override func tearDownWithError() throws {
        testDefaults = nil
        service = nil
    }

    // MARK: - Relay URL Tests

    /// Scenario: Default relay URL is set
    func testDefaultRelayUrl() {
        XCTAssertEqual(SettingsService.defaultRelayUrl, "wss://relay.vauchi.app")
        XCTAssertEqual(service.relayUrl, SettingsService.defaultRelayUrl)
    }

    /// Scenario: Validate valid WebSocket URLs
    func testValidRelayUrls() {
        XCTAssertTrue(service.isValidRelayUrl("ws://localhost:8080"))
        XCTAssertTrue(service.isValidRelayUrl("wss://relay.vauchi.app"))
        XCTAssertTrue(service.isValidRelayUrl("wss://relay.example.com:443/path"))
    }

    /// Scenario: Reject invalid relay URLs
    func testInvalidRelayUrls() {
        XCTAssertFalse(service.isValidRelayUrl("http://localhost:8080"))
        XCTAssertFalse(service.isValidRelayUrl("https://relay.vauchi.app"))
        XCTAssertFalse(service.isValidRelayUrl("not-a-url"))
        XCTAssertFalse(service.isValidRelayUrl(""))
        XCTAssertFalse(service.isValidRelayUrl("ftp://files.example.com"))
    }

    /// Scenario: Relay URL persists
    func testRelayUrlPersistence() {
        let testUrl = "wss://custom-relay.example.com:8080"

        service.relayUrl = testUrl
        XCTAssertEqual(service.relayUrl, testUrl)

        // Create new service with same defaults to verify persistence
        let service2 = SettingsService(defaults: testDefaults)
        XCTAssertEqual(service2.relayUrl, testUrl)
    }

    // MARK: - Sync Settings Tests

    /// Scenario: Last sync time is nil initially
    func testInitialLastSyncTimeIsNil() {
        XCTAssertNil(service.lastSyncTime)
    }

    /// Scenario: Last sync time can be set and retrieved
    func testLastSyncTimePersistence() {
        let testDate = Date()

        service.lastSyncTime = testDate

        XCTAssertNotNil(service.lastSyncTime)
        if let retrieved = service.lastSyncTime {
            XCTAssertEqual(retrieved.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 1.0)
        }

        // Create new service to verify persistence
        let service2 = SettingsService(defaults: testDefaults)
        XCTAssertNotNil(service2.lastSyncTime)
    }

    /// Scenario: Last sync time can be cleared
    func testClearLastSyncTime() {
        service.lastSyncTime = Date()
        XCTAssertNotNil(service.lastSyncTime)

        service.lastSyncTime = nil
        XCTAssertNil(service.lastSyncTime)
    }

    /// Scenario: Auto sync enabled by default
    func testAutoSyncEnabledByDefault() {
        XCTAssertTrue(service.autoSyncEnabled)
    }

    /// Scenario: Toggle auto sync setting
    func testToggleAutoSync() {
        XCTAssertTrue(service.autoSyncEnabled)

        service.autoSyncEnabled = false
        XCTAssertFalse(service.autoSyncEnabled)

        service.autoSyncEnabled = true
        XCTAssertTrue(service.autoSyncEnabled)
    }

    /// Scenario: Sync on launch enabled by default
    func testSyncOnLaunchEnabledByDefault() {
        XCTAssertTrue(service.syncOnLaunch)
    }

    // MARK: - Notification Settings Tests

    /// Scenario: Notifications enabled by default
    func testNotificationsEnabledByDefault() {
        XCTAssertTrue(service.notificationsEnabled)
    }

    /// Scenario: Toggle notifications setting
    func testToggleNotifications() {
        XCTAssertTrue(service.notificationsEnabled)

        service.notificationsEnabled = false
        XCTAssertFalse(service.notificationsEnabled)

        service.notificationsEnabled = true
        XCTAssertTrue(service.notificationsEnabled)
    }

    // MARK: - Reset Tests

    /// Scenario: Reset restores default values
    func testResetRestoresDefaults() {
        // Change all settings
        service.relayUrl = "wss://custom.example.com"
        service.autoSyncEnabled = false
        service.syncOnLaunch = false
        service.notificationsEnabled = false
        service.lastSyncTime = Date()

        // Reset
        service.resetToDefaults()

        // Verify defaults are restored
        XCTAssertEqual(service.relayUrl, SettingsService.defaultRelayUrl)
        XCTAssertTrue(service.autoSyncEnabled)
        XCTAssertTrue(service.syncOnLaunch)
        XCTAssertTrue(service.notificationsEnabled)
        XCTAssertNil(service.lastSyncTime)
    }
}
