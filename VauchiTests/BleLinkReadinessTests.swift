// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import VauchiPlatform
import XCTest

final class BleLinkReadinessTests: XCTestCase {
    private func events(subscribedTo uuid: String, length: Int = 182) -> [MobileEvent] {
        BleLinkReadiness.events(
            subscribedTo: uuid, deviceId: "central", maximumUpdateValueLength: length
        )
    }

    func testSubscribingToDataNotifyReportsTheMtuThenReadiness() {
        XCTAssertEqual(
            events(subscribedTo: BleUuids.dataNotify),
            [.bleMtuNegotiated(deviceId: "central", mtu: 185), .bleGattReady(deviceId: "central")]
        )
    }

    func testCoreBluetoothsUpperCaseUuidStillMatches() {
        XCTAssertEqual(
            events(subscribedTo: BleUuids.dataNotify.uppercased()),
            [.bleMtuNegotiated(deviceId: "central", mtu: 185), .bleGattReady(deviceId: "central")]
        )
    }

    func testSubscribingToAnotherCharacteristicReportsNothing() {
        XCTAssertEqual(events(subscribedTo: BleUuids.handshakeNotify), [])
    }

    func testANegativeLengthCannotCrashTheConversion() {
        XCTAssertEqual(
            events(subscribedTo: BleUuids.dataNotify, length: -1),
            [.bleMtuNegotiated(deviceId: "central", mtu: 3), .bleGattReady(deviceId: "central")]
        )
    }
}
