// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// A shred destroys the key that opens the data, not only the files
// (vauchi/private#580, ADR-033, ship checklist SC-24): a copy of the data
// directory taken before the shred and put back afterwards no longer
// opens, through the real engine and the real keychain bridge over a fake
// keychain store.

@testable import Vauchi
import VauchiPlatform
import XCTest

final class ShredDestroysTheStorageKeyTests: XCTestCase {
    private var dataDir: URL!
    private var copyDir: URL!
    private var store: FakeKeychainStore!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        dataDir = root.appendingPathComponent("data")
        copyDir = root.appendingPathComponent("data-before-shred")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        store = FakeKeychainStore()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dataDir.deletingLastPathComponent())
    }

    private func open() throws -> VauchiRepository {
        try VauchiRepository(dataDir: dataDir.path, keychain: VauchiKeychainBridge(keychain: store))
    }

    /// Alice's install, closed, and a copy of her data directory as an
    /// imager would take it.
    private func aliceWithACopyOfHerData() throws {
        do {
            let repository = try open()
            try repository.createIdentity(displayName: "Alice")
            XCTAssertTrue(repository.hasIdentity())
        }
        try FileManager.default.copyItem(at: dataDir, to: copyDir)
    }

    /// The shred may remove the data directory itself, so only what is
    /// left of it goes before the copy comes back.
    private func putTheCopyBack() throws {
        if FileManager.default.fileExists(atPath: dataDir.path) {
            try FileManager.default.removeItem(at: dataDir)
        }
        try FileManager.default.copyItem(at: copyDir, to: dataDir)
    }

    func testShredDestroysTheStorageKey() throws {
        try aliceWithACopyOfHerData()

        _ = try widgetPanicShred(
            dataDir: dataDir.path,
            keychain: VauchiKeychainBridge(keychain: store)
        )
        try putTheCopyBack()

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dataDir.appendingPathComponent("vauchi.db").path
        ))
        XCTAssertFalse(
            try open().hasIdentity(),
            "a copy of the data taken before the shred still opens"
        )
    }

    func testACopyPutBackWithoutAShredStillOpens() throws {
        try aliceWithACopyOfHerData()

        try putTheCopyBack()

        XCTAssertTrue(try open().hasIdentity())
    }
}
