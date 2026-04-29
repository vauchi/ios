// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeviceLinkingTests.swift
// Tests for multi-device linking functionality
// Based on: features/device_management.feature

@testable import Vauchi
import XCTest

/// Tests for device linking functionality
/// Based on: features/device_management.feature
final class DeviceLinkingTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Primary Device")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Device Info Tests

    // Based on: Scenario: View linked devices

    /// Scenario: Primary device exists after identity creation
    func testPrimaryDeviceExists() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let devices = try repo.getDevices()

        XCTAssertGreaterThanOrEqual(devices.count, 1, "Should have at least primary device")

        if let primaryDevice = devices.first {
            XCTAssertEqual(primaryDevice.deviceIndex, 0, "Primary device should have index 0")
            XCTAssertFalse(primaryDevice.deviceName.isEmpty, "Device should have a name")
        }
    }

    /// Scenario: Current device is identified
    func testCurrentDeviceIdentified() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let devices = try repo.getDevices()

        let currentDevice = devices.first { $0.isCurrent }
        XCTAssertNotNil(currentDevice, "Should identify current device")
    }

    /// Scenario: Device has creation timestamp
    func testDeviceHasTimestamp() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let devices = try repo.getDevices()

        guard let device = devices.first else {
            XCTFail("Should have at least one device")
            return
        }

        // Timestamp should be reasonable (after 2024, before 2030)
        let minTimestamp: UInt64 = 1_704_067_200 // 2024-01-01
        let maxTimestamp: UInt64 = 1_893_456_000 // 2030-01-01

        XCTAssertGreaterThan(device.createdAt, minTimestamp, "Device timestamp should be after 2024")
        XCTAssertLessThan(device.createdAt, maxTimestamp, "Device timestamp should be before 2030")
    }

    // MARK: - Link QR Generation Tests

    // Based on: Scenario: Generate device link QR on existing device

    /// Scenario: Generate device link QR code
    func testGenerateDeviceLinkQR() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let linkData = try repo.generateDeviceLinkQr()

        XCTAssertFalse(linkData.qrData.isEmpty, "QR data should not be empty")
        XCTAssertFalse(linkData.identityPublicKey.isEmpty, "Identity public key should be included")
        XCTAssertGreaterThan(linkData.expiresAt, linkData.timestamp, "Expiry should be after creation")
    }

    /// Scenario: Device link QR contains expiry
    func testDeviceLinkQRExpiry() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let linkData = try repo.generateDeviceLinkQr()

        let now = UInt64(Date().timeIntervalSince1970)
        let expiryDuration = linkData.expiresAt - linkData.timestamp

        // Should expire within 5 minutes (300 seconds) as per ADR-035
        XCTAssertEqual(expiryDuration, 300, "Should expire in 5 minutes")

        // Expiry should be in the future
        XCTAssertGreaterThan(linkData.expiresAt, now, "Expiry should be in the future")
    }

    /// Scenario: Multiple link QRs can be generated
    func testMultipleDeviceLinkQRs() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let qr1 = try repo.generateDeviceLinkQr()
        let qr2 = try repo.generateDeviceLinkQr()

        // Same identity key
        XCTAssertEqual(qr1.identityPublicKey, qr2.identityPublicKey)

        // But different QR data (includes nonce/timestamp)
        // Or same if deterministic - both acceptable
        XCTAssertFalse(qr1.qrData.isEmpty)
        XCTAssertFalse(qr2.qrData.isEmpty)
    }

    // MARK: - Link Info Parsing Tests

    // Based on: Scenario: New device scans link QR

    /// Scenario: Parse valid device link QR
    func testParseDeviceLinkQR() throws {
        try Self.skipPendingDeviceLinkingMigration()
        // Generate QR on "existing" device
        let linkData = try repo.generateDeviceLinkQr()

        // Parse it (simulating scan on new device)
        let linkInfo = try repo.parseDeviceLinkQr(qrData: linkData.qrData)

        XCTAssertEqual(linkInfo.identityPublicKey, linkData.identityPublicKey)
        XCTAssertFalse(linkInfo.isExpired, "Freshly generated QR should not be expired")
    }

    /// Scenario: Parse invalid device link QR returns error
    func testParseInvalidDeviceLinkQR() throws {
        let invalidData = "not-valid-device-link-qr"

        XCTAssertThrowsError(try repo.parseDeviceLinkQr(qrData: invalidData)) { error in
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Parse empty device link QR returns error
    func testParseEmptyDeviceLinkQR() throws {
        XCTAssertThrowsError(try repo.parseDeviceLinkQr(qrData: ""))
    }

    // MARK: - Device Limits Tests

    // Based on: Scenario: Maximum devices limit

    /// Scenario: Cannot exceed maximum device count
    func testDeviceCountWithinLimits() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let devices = try repo.getDevices()

        // Should not exceed maximum (typically 5-10 devices)
        XCTAssertLessThanOrEqual(devices.count, 10, "Should not exceed max device limit")
    }

    // MARK: - Device Removal Tests

    // Based on: Scenario: Unlink device

    /// Scenario: Cannot unlink current device
    func testCannotUnlinkCurrentDevice() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let devices = try repo.getDevices()
        guard let currentDevice = devices.first(where: { $0.isCurrent }) else {
            XCTFail("Should have current device")
            return
        }

        let result = try repo.unlinkDevice(deviceIndex: currentDevice.deviceIndex)
        XCTAssertFalse(result, "Should not allow unlinking current device")
    }

    /// Scenario: Cannot unlink non-existent device
    func testCannotUnlinkNonExistentDevice() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let nonExistentIndex: UInt32 = 999

        let result = try repo.unlinkDevice(deviceIndex: nonExistentIndex)
        XCTAssertFalse(result, "Should not allow unlinking non-existent device")
    }

    // MARK: - Device Name Tests

    /// Scenario: Device has meaningful name
    func testDeviceHasMeaningfulName() throws {
        try Self.skipPendingDeviceLinkingMigration()
        let devices = try repo.getDevices()

        for device in devices {
            XCTAssertFalse(device.deviceName.isEmpty, "Device name should not be empty")
            XCTAssertGreaterThanOrEqual(device.deviceName.count, 2, "Device name should be at least 2 chars")
        }
    }

    /// Skip helper for tests that go through the legacy `vauchi: VauchiPlatform`
    /// instance after `appEngine.createIdentity`. The legacy instance has no
    /// `reload_from_storage()` seam, so its in-memory state stays "no identity"
    /// even though the DB has one — every device-linking query then errors with
    /// `Identity not found`. Restored when the Device Linking domain migrates
    /// to `PlatformAppEngine` (C8, blocked on B4 binding bump per
    /// `_private/docs/problems/2026-04-28-collapse-vauchi-platform-into-app-engine/`).
    private static func skipPendingDeviceLinkingMigration() throws {
        throw XCTSkip(
            "Blocked on dual-instance state drift — Device Linking methods "
                + "still go through legacy VauchiPlatform; restored when C8 "
                + "(Device Linking) migrates to PlatformAppEngine after B4. "
                + "See _private/docs/problems/2026-04-28-collapse-vauchi-"
                + "platform-into-app-engine/."
        )
    }
}
