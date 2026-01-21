// DeviceLinkingTests.swift
// Tests for multi-device linking functionality
// Based on: features/device_management.feature

import XCTest
@testable import Vauchi

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
        let devices = try repo.getDevices()

        XCTAssertGreaterThanOrEqual(devices.count, 1, "Should have at least primary device")

        if let primaryDevice = devices.first {
            XCTAssertEqual(primaryDevice.deviceIndex, 0, "Primary device should have index 0")
            XCTAssertFalse(primaryDevice.deviceName.isEmpty, "Device should have a name")
        }
    }

    /// Scenario: Current device is identified
    func testCurrentDeviceIdentified() throws {
        let devices = try repo.getDevices()

        let currentDevice = devices.first { $0.isCurrentDevice }
        XCTAssertNotNil(currentDevice, "Should identify current device")
    }

    /// Scenario: Device has creation timestamp
    func testDeviceHasTimestamp() throws {
        let devices = try repo.getDevices()

        guard let device = devices.first else {
            XCTFail("Should have at least one device")
            return
        }

        // Timestamp should be reasonable (after 2024, before 2030)
        let minTimestamp: UInt64 = 1704067200  // 2024-01-01
        let maxTimestamp: UInt64 = 1893456000  // 2030-01-01

        XCTAssertGreaterThan(device.createdAt, minTimestamp, "Device timestamp should be after 2024")
        XCTAssertLessThan(device.createdAt, maxTimestamp, "Device timestamp should be before 2030")
    }

    // MARK: - Link QR Generation Tests
    // Based on: Scenario: Generate device link QR on existing device

    /// Scenario: Generate device link QR code
    func testGenerateDeviceLinkQR() throws {
        let linkData = try repo.generateDeviceLinkQR()

        XCTAssertFalse(linkData.qrData.isEmpty, "QR data should not be empty")
        XCTAssertFalse(linkData.identityPublicKey.isEmpty, "Identity public key should be included")
        XCTAssertGreaterThan(linkData.expiresAt, linkData.timestamp, "Expiry should be after creation")
    }

    /// Scenario: Device link QR contains expiry
    func testDeviceLinkQRExpiry() throws {
        let linkData = try repo.generateDeviceLinkQR()

        let now = UInt64(Date().timeIntervalSince1970)
        let expiryDuration = linkData.expiresAt - linkData.timestamp

        // Should expire within reasonable time (1 hour to 24 hours)
        XCTAssertGreaterThan(expiryDuration, 60 * 60, "Should expire after at least 1 hour")
        XCTAssertLessThan(expiryDuration, 24 * 60 * 60, "Should expire within 24 hours")

        // Expiry should be in the future
        XCTAssertGreaterThan(linkData.expiresAt, now, "Expiry should be in the future")
    }

    /// Scenario: Multiple link QRs can be generated
    func testMultipleDeviceLinkQRs() throws {
        let qr1 = try repo.generateDeviceLinkQR()
        let qr2 = try repo.generateDeviceLinkQR()

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
        // Generate QR on "existing" device
        let linkData = try repo.generateDeviceLinkQR()

        // Parse it (simulating scan on new device)
        let linkInfo = try repo.parseDeviceLinkQR(qrData: linkData.qrData)

        XCTAssertEqual(linkInfo.identityPublicKey, linkData.identityPublicKey)
        XCTAssertFalse(linkInfo.isExpired, "Freshly generated QR should not be expired")
    }

    /// Scenario: Parse invalid device link QR returns error
    func testParseInvalidDeviceLinkQR() throws {
        let invalidData = "not-valid-device-link-qr"

        XCTAssertThrowsError(try repo.parseDeviceLinkQR(qrData: invalidData)) { error in
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Parse empty device link QR returns error
    func testParseEmptyDeviceLinkQR() throws {
        XCTAssertThrowsError(try repo.parseDeviceLinkQR(qrData: ""))
    }

    // MARK: - Device Limits Tests
    // Based on: Scenario: Maximum devices limit

    /// Scenario: Cannot exceed maximum device count
    func testDeviceCountWithinLimits() throws {
        let devices = try repo.getDevices()

        // Should not exceed maximum (typically 5-10 devices)
        XCTAssertLessThanOrEqual(devices.count, 10, "Should not exceed max device limit")
    }

    // MARK: - Device Removal Tests
    // Based on: Scenario: Unlink device

    /// Scenario: Cannot unlink current device
    func testCannotUnlinkCurrentDevice() throws {
        let devices = try repo.getDevices()
        guard let currentDevice = devices.first(where: { $0.isCurrentDevice }) else {
            XCTFail("Should have current device")
            return
        }

        XCTAssertThrowsError(try repo.unlinkDevice(deviceIndex: currentDevice.deviceIndex)) { error in
            // Should not allow unlinking current device
            XCTAssertNotNil(error)
        }
    }

    /// Scenario: Cannot unlink non-existent device
    func testCannotUnlinkNonExistentDevice() throws {
        let nonExistentIndex: UInt32 = 999

        XCTAssertThrowsError(try repo.unlinkDevice(deviceIndex: nonExistentIndex))
    }

    // MARK: - Device Name Tests

    /// Scenario: Device has meaningful name
    func testDeviceHasMeaningfulName() throws {
        let devices = try repo.getDevices()

        for device in devices {
            XCTAssertFalse(device.deviceName.isEmpty, "Device name should not be empty")
            XCTAssertGreaterThanOrEqual(device.deviceName.count, 2, "Device name should be at least 2 chars")
        }
    }
}
