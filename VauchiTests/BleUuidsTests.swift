// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreBluetooth
@testable import Vauchi
import XCTest

/// Pins the role-tiebreak token <-> 16-bit service UUID encoding (P5c
/// unified advertisement format, v2), mirroring Android's `BleUuidsTest`.
///
/// 16-bit, not 32-bit: pre-Android-9 stacks truncate a 32-bit service
/// UUID to its low 16 bits when advertising (`ff5b2478` went on air as
/// `00002478`), which deadlocked the role tiebreak with both peers as
/// responder. Only the 16-bit compressed form survives every stack
/// intact. See `2026-06-06-android-ble-execution` (P5b re-test,
/// 2026-06-10).
final class BleUuidsTests: XCTestCase {
    func testTokenRoundTripsThroughA16BitServiceUUID() {
        let token = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])
        let uuid = BleUuids.tokenToServiceUUID(token)
        XCTAssertEqual(
            BleUuids.tokenFromServiceUUID(uuid),
            token.prefix(BleUuids.advTokenBytes)
        )
    }

    func testAdvTokenIsTwoBytes() {
        // The tiebreak prefix compare needs token[0..advTokenBytes];
        // widening it again would reintroduce the pre-Android-9
        // truncation deadlock.
        XCTAssertEqual(BleUuids.advTokenBytes, 2)
    }

    func testEncodedUUIDIsA16BitUUID() {
        let uuid = BleUuids.tokenToServiceUUID(Data([0x10, 0x42]))
        XCTAssertEqual(uuid, CBUUID(string: "1042"))
    }

    func testLegacy32BitUUIDDecodesToItsFourByteToken() {
        // Transition compat: an un-updated peer still advertises the
        // 4-byte token as a 32-bit UUID; decode it whole so the
        // full-vs-prefix compare stays consistent.
        let uuid = CBUUID(data: Data([0xF9, 0x10, 0xC8, 0xE8]))
        XCTAssertEqual(
            BleUuids.tokenFromServiceUUID(uuid),
            Data([0xF9, 0x10, 0xC8, 0xE8])
        )
    }

    func testThe128BitServiceUUIDIsNotMistakenForAToken() {
        XCTAssertNil(BleUuids.tokenFromServiceUUID(CBUUID(string: BleUuids.service)))
    }

    func testShortTokenRoundTripsZeroPadded() {
        let uuid = BleUuids.tokenToServiceUUID(Data([0xAB]))
        XCTAssertEqual(BleUuids.tokenFromServiceUUID(uuid), Data([0xAB, 0x00]))
    }
}
