// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core opens storage through the keychain (vauchi/private#580). The storage
// key this app kept before is served as Core's bootstrap key until Core moves
// the data to its own keys, and a locked keychain reaches Core as its own
// kind, so Core shows its unlock screen.

@testable import Vauchi
import VauchiPlatform
import XCTest

final class VauchiKeychainBridgeHandoverTests: XCTestCase {
    private var store: FakeKeychainStore!
    private var bridge: VauchiKeychainBridge!

    override func setUp() {
        store = FakeKeychainStore()
        bridge = VauchiKeychainBridge(keychain: store)
    }

    func testTheOldStorageKeyIsTheBootstrapKeyUntilCoreStoresItsOwn() throws {
        let oldKey = Data(repeating: 7, count: 32)
        store.items["storage_key"] = oldKey

        XCTAssertEqual(try bridge.loadKey(name: "storage_bootstrap"), oldKey)

        let coreKey = Data(repeating: 9, count: 32)
        try bridge.saveKey(name: "storage_bootstrap", key: coreKey)
        XCTAssertEqual(try bridge.loadKey(name: "storage_bootstrap"), coreKey)
    }

    func testOnlyTheBootstrapNameFallsBackToTheOldKey() throws {
        store.items["storage_key"] = Data(repeating: 7, count: 32)

        XCTAssertNil(try bridge.loadKey(name: "smk"))
    }

    func testAnOldKeyOfAnotherLengthReachesCoreUnchanged() throws {
        let shortKey = Data(repeating: 1, count: 16)
        store.items["storage_key"] = shortKey

        XCTAssertEqual(try bridge.loadKey(name: "storage_bootstrap"), shortKey)
    }

    func testDeletingTheBootstrapKeyDeletesTheOldKeyToo() throws {
        store.items["storage_key"] = Data(repeating: 7, count: 32)
        try bridge.saveKey(name: "storage_bootstrap", key: Data(repeating: 9, count: 32))

        try bridge.deleteKey(name: "storage_bootstrap")

        XCTAssertNil(store.items["storage_key"])
        XCTAssertNil(try bridge.loadKey(name: "storage_bootstrap"))
    }

    func testALockedKeychainReachesCoreAsAuthenticationRequired() {
        store.failure = KeychainServiceError.deviceLocked

        XCTAssertThrowsError(try bridge.loadKey(name: "storage_bootstrap")) { error in
            XCTAssertEqual(error as? KeychainError, .AuthenticationRequired)
        }
        XCTAssertThrowsError(try bridge.saveKey(name: "smk", key: Data(repeating: 1, count: 32))) { error in
            XCTAssertEqual(error as? KeychainError, .AuthenticationRequired)
        }
    }
}
