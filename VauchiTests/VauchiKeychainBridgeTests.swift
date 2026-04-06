// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VauchiKeychainBridgeTests.swift
// Tests for VauchiKeychainBridge — MobilePlatformKeychain adapter over KeychainService

@testable import Vauchi
import XCTest

final class VauchiKeychainBridgeTests: XCTestCase {
    var bridge: VauchiKeychainBridge!
    let testKeyName = "__bridge_test_key__"

    override func setUpWithError() throws {
        bridge = VauchiKeychainBridge()
        try? bridge.deleteKey(name: testKeyName)
    }

    override func tearDownWithError() throws {
        try? bridge.deleteKey(name: testKeyName)
    }

    // MARK: - Round-trip Tests

    /// Scenario: Save and load returns the same key data
    func test_save_then_load_round_trips() throws {
        let keyData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])

        try bridge.saveKey(name: testKeyName, key: keyData)
        let loaded = try bridge.loadKey(name: testKeyName)

        XCTAssertEqual(loaded, keyData)
    }

    /// Scenario: Load non-existent key returns nil (not an error)
    func test_load_nonexistent_returns_nil() throws {
        let loaded = try bridge.loadKey(name: "__nonexistent_key__")

        XCTAssertNil(loaded)
    }

    /// Scenario: Delete removes key so subsequent load returns nil
    func test_delete_then_load_returns_nil() throws {
        let keyData = Data([0x01, 0x02, 0x03])
        try bridge.saveKey(name: testKeyName, key: keyData)

        try bridge.deleteKey(name: testKeyName)
        let loaded = try bridge.loadKey(name: testKeyName)

        XCTAssertNil(loaded)
    }

    /// Scenario: Save overwrites existing key
    func test_save_overwrites_existing() throws {
        let original = Data([0x01, 0x02])
        let updated = Data([0x03, 0x04, 0x05])

        try bridge.saveKey(name: testKeyName, key: original)
        try bridge.saveKey(name: testKeyName, key: updated)
        let loaded = try bridge.loadKey(name: testKeyName)

        XCTAssertEqual(loaded, updated)
    }

    /// Scenario: Delete non-existent key does not throw
    func test_delete_nonexistent_does_not_throw() throws {
        XCTAssertNoThrow(try bridge.deleteKey(name: "__never_saved__"))
    }

    /// Scenario: 32-byte key (SMK size) round-trips correctly
    func test_smk_sized_key_round_trips() throws {
        var keyBytes = [UInt8](repeating: 0, count: 32)
        for i in 0 ..< 32 {
            keyBytes[i] = UInt8(i)
        }
        let keyData = Data(keyBytes)

        try bridge.saveKey(name: testKeyName, key: keyData)
        let loaded = try bridge.loadKey(name: testKeyName)

        XCTAssertEqual(loaded, keyData)
        XCTAssertEqual(loaded?.count, 32)
    }
}
