// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// An install from before vauchi/private#580 upgrades through the real Core:
// the old key reads, and the keychain may take a write only after the
// person unlocks, as on the rig's Android phones.
//
// Traces to: features/storage_key_upgrade.feature

@testable import Vauchi
import VauchiPlatform
import XCTest

final class StorageKeyUpgradeTests: XCTestCase {
    private var tempDir: URL!
    private var store: FakeKeychainStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try LegacyInstall.before.copy(into: tempDir)
        store = FakeKeychainStore()
        store.items["storage_key"] = LegacyInstall.storageKey
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func open() throws -> VauchiRepository {
        try VauchiRepository(dataDir: tempDir.path, keychain: VauchiKeychainBridge(keychain: store))
    }

    private func surface(_ engine: PlatformAppEngine) throws -> String? {
        let batch = try engine.initialCommandsJson()
        guard let range = batch.range(of: #""surface_id":"([^"]+)""#, options: .regularExpression)
        else { return nil }
        return String(batch[range]).components(separatedBy: "\"")[3]
    }

    private func contactCount(_ engine: PlatformAppEngine) throws -> UInt32? {
        guard case let .count(value) = try engine.dispatchDomainCommand(command: .contactCount) else { return nil }
        return value
    }

    func testTheUpgradeKeepsEverythingAndLeavesOnlyCoresKey() throws {
        let engine = try open().appEngine

        XCTAssertEqual(try engine.hasIdentity(), true)
        XCTAssertEqual(try contactCount(engine), 1)
        XCTAssertEqual(store.items.keys.sorted(), ["smk"])
    }

    func testAKeychainThatNeedsAnUnlockStartsOnCoresUnlockScreen() throws {
        store.saveFailure = KeychainServiceError.deviceLocked

        let engine = try open().appEngine

        XCTAssertEqual(try surface(engine), "storage_lock.locked")
        XCTAssertEqual(store.items.keys.sorted(), ["storage_key"])
    }

    func testUnlockingFinishesTheUpgrade() throws {
        store.saveFailure = KeychainServiceError.deviceLocked
        let engine = try open().appEngine
        _ = try engine.initialCommandsJson()

        store.saveFailure = nil
        _ = try engine.dispatchJson(eventJson: #""BiometricUnlockSucceeded""#)

        XCTAssertEqual(try engine.hasIdentity(), true)
        XCTAssertEqual(try contactCount(engine), 1)
        XCTAssertEqual(store.items.keys.sorted(), ["smk"])
    }

    func testAKeychainThatFailsForAnotherReasonOffersTryAgain() throws {
        store.saveFailure = KeychainServiceError.unknown(-1)

        let engine = try open().appEngine

        XCTAssertEqual(try surface(engine), "storage_lock.unavailable")
        XCTAssertEqual(store.items.keys.sorted(), ["storage_key"])
    }
}
