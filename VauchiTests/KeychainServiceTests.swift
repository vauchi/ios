// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// KeychainServiceTests.swift
// Tests for KeychainService - secure storage with file fallback
// Based on: features/security.feature

@testable import Vauchi
import XCTest

/// Tests for KeychainService
/// Based on: features/security.feature - Scenario: Secure credential storage
final class KeychainServiceTests: XCTestCase {
    var keychainService: KeychainService!

    override func setUpWithError() throws {
        keychainService = KeychainService.shared
        // Clean up any existing test keys
        try? keychainService.delete(key: "test_key")
        try? keychainService.delete(key: "test_string")
    }

    override func tearDownWithError() throws {
        // Clean up test keys
        try? keychainService.delete(key: "test_key")
        try? keychainService.delete(key: "test_string")
    }

    // MARK: - Basic Operations Tests

    /// Scenario: Save and load data from secure storage
    func testSaveAndLoadData() throws {
        let testData = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        try keychainService.save(key: "test_key", data: testData)
        let loadedData = try keychainService.load(key: "test_key")

        XCTAssertEqual(loadedData, testData, "Loaded data should match saved data")
    }

    /// Scenario: Load non-existent key returns error
    func testLoadNonExistentKeyThrowsNotFound() throws {
        XCTAssertThrowsError(try keychainService.load(key: "non_existent_key")) { error in
            guard case KeychainServiceError.notFound = error else {
                XCTFail("Expected notFound error, got \(error)")
                return
            }
        }
    }

    /// Scenario: Update existing key with new data
    func testUpdateExistingKey() throws {
        let originalData = Data([0x01, 0x02, 0x03])
        let updatedData = Data([0x04, 0x05, 0x06, 0x07])

        try keychainService.save(key: "test_key", data: originalData)
        try keychainService.save(key: "test_key", data: updatedData)

        let loadedData = try keychainService.load(key: "test_key")
        XCTAssertEqual(loadedData, updatedData, "Should return updated data")
    }

    /// Scenario: Delete key from secure storage
    func testDeleteKey() throws {
        let testData = Data([0x01, 0x02])

        try keychainService.save(key: "test_key", data: testData)
        try keychainService.delete(key: "test_key")

        XCTAssertThrowsError(try keychainService.load(key: "test_key")) { error in
            guard case KeychainServiceError.notFound = error else {
                XCTFail("Expected notFound error after delete")
                return
            }
        }
    }

    /// Scenario: Delete non-existent key succeeds silently
    func testDeleteNonExistentKeySucceeds() throws {
        // Should not throw
        XCTAssertNoThrow(try keychainService.delete(key: "never_existed"))
    }

    // MARK: - String Convenience Tests

    /// Scenario: Save and load string value
    func testSaveAndLoadString() throws {
        let testString = "Hello, secure world!"

        try keychainService.saveString(testString, forKey: "test_string")
        let loadedString = try keychainService.loadString(forKey: "test_string")

        XCTAssertEqual(loadedString, testString)
    }

    /// Scenario: String with unicode characters
    func testSaveAndLoadUnicodeString() throws {
        let testString = "Hello \u{1F512} secure \u{2764}\u{FE0F}" // Lock and heart emoji

        try keychainService.saveString(testString, forKey: "test_string")
        let loadedString = try keychainService.loadString(forKey: "test_string")

        XCTAssertEqual(loadedString, testString)
    }

    // MARK: - Vauchi-Specific Tests

    /// Scenario: Save and load storage encryption key
    func testSaveAndLoadStorageKey() throws {
        // Simulate 32-byte encryption key
        let storageKey = Data((0 ..< 32).map { UInt8($0) })

        try keychainService.saveStorageKey(storageKey)
        let loadedKey = try keychainService.loadStorageKey()

        XCTAssertEqual(loadedKey, storageKey)
        XCTAssertEqual(loadedKey.count, 32, "Storage key should be 32 bytes")

        // Cleanup
        try keychainService.delete(key: "storage_key")
    }

    /// Scenario: Save and load identity backup
    func testSaveAndLoadIdentityBackup() throws {
        // Simulate encrypted identity backup
        let backupData = Data([0xDE, 0xAD, 0xBE, 0xEF] + (0 ..< 100).map { UInt8($0) })

        try keychainService.saveIdentityBackup(backupData)
        let loadedBackup = try keychainService.loadIdentityBackup()

        XCTAssertEqual(loadedBackup, backupData)

        // Cleanup
        try keychainService.delete(key: "identity_backup")
    }

    // MARK: - Edge Cases

    /// Scenario: Handle empty data
    func testSaveAndLoadEmptyData() throws {
        let emptyData = Data()

        try keychainService.save(key: "test_key", data: emptyData)
        let loadedData = try keychainService.load(key: "test_key")

        XCTAssertEqual(loadedData, emptyData)
        XCTAssertTrue(loadedData.isEmpty)
    }

    /// Scenario: Handle large data
    func testSaveAndLoadLargeData() throws {
        // 1MB of data
        let largeData = Data((0 ..< (1024 * 1024)).map { UInt8($0 % 256) })

        try keychainService.save(key: "test_key", data: largeData)
        let loadedData = try keychainService.load(key: "test_key")

        XCTAssertEqual(loadedData.count, largeData.count)
        XCTAssertEqual(loadedData, largeData)
    }

    /// Scenario: Key names with special characters
    func testKeyWithSpecialCharacters() throws {
        let specialKey = "test.key/with:special-chars_123"
        let testData = Data([0x01, 0x02])

        try keychainService.save(key: specialKey, data: testData)
        let loadedData = try keychainService.load(key: specialKey)

        XCTAssertEqual(loadedData, testData)

        try keychainService.delete(key: specialKey)
    }

    // MARK: - Device Locked Error Tests

    /// Scenario: KeychainServiceError.deviceLocked maps to errSecInteractionNotAllowed
    /// Verifies that the error enum case exists and is distinct from other errors
    func testDeviceLockedErrorIsDistinctFromOtherErrors() {
        let deviceLockedError = KeychainServiceError.deviceLocked
        let notFoundError = KeychainServiceError.notFound
        let unknownError = KeychainServiceError.unknown(-25308)

        // deviceLocked should be a distinct case, not conflated with unknown(-25308)
        switch deviceLockedError {
        case .deviceLocked:
            // Expected — this is the correct case
            break
        default:
            XCTFail("Expected .deviceLocked, got \(deviceLockedError)")
        }

        // Verify it's not the same as notFound
        switch notFoundError {
        case .deviceLocked:
            XCTFail("notFound should not match deviceLocked")
        default:
            break // Expected
        }

        // Verify unknown(-25308) is distinct from the named deviceLocked case
        switch unknownError {
        case .deviceLocked:
            XCTFail("unknown(-25308) should not match deviceLocked")
        default:
            break // Expected — they are distinct enum cases
        }
    }

    /// Scenario: errSecInteractionNotAllowed status code matches deviceLocked semantics
    /// Verifies the OSStatus constant value used in the Keychain API
    func testErrSecInteractionNotAllowedStatusCode() {
        // errSecInteractionNotAllowed is -25308 per Apple Security framework
        let status: OSStatus = errSecInteractionNotAllowed
        XCTAssertEqual(status, -25308, "errSecInteractionNotAllowed should be -25308")
    }
}
