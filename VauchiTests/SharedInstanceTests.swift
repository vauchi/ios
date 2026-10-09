// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// The foreground view model and the background sync handler share one
// repository, so one engine holds the database. A second engine opened under
// one key goes stale when the first moves the data to another key
// (vauchi/private#580, T5.0).

@testable import Vauchi
import XCTest

final class SharedInstanceTests: XCTestCase {
    private final class Made {}
    private struct CreationFailed: Error {}

    func testEveryCallerGetsTheSameInstance() throws {
        let shared = SharedInstance<Made>()
        var created = 0
        let make = { () throws -> Made in
            created += 1
            return Made()
        }

        let first = try shared.get(orMake: make)
        let second = try shared.get(orMake: make)

        XCTAssertTrue(first === second)
        XCTAssertEqual(created, 1)
    }

    func testAFailedCreationIsTriedAgainNextTime() throws {
        let shared = SharedInstance<Made>()
        var attempts = 0
        let make = { () throws -> Made in
            attempts += 1
            if attempts == 1 {
                throw CreationFailed()
            }
            return Made()
        }

        XCTAssertThrowsError(try shared.get(orMake: make))
        let made = try shared.get(orMake: make)

        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(try made === (shared.get(orMake: make)))
    }

    func testTheRepositoryHolderIsShared() {
        XCTAssertTrue(VauchiRepository.shared === VauchiRepository.shared)
    }
}
