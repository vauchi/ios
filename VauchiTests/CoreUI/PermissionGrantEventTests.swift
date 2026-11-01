// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// iOS raises the Bluetooth and camera prompts itself, so Core never learned
// when one was granted and Glance's 15 s search ran down while the prompt
// was open (vauchi/private#1022). The shell now reports the grant as Core's
// canonical `Event::PermissionGranted`; the generated `MobileEvent` has no
// such case, so it goes as event JSON.

import CoreBluetooth
@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class PermissionGrantEventTests: XCTestCase {
    func testTheGrantIsCoresCanonicalPermissionGrantedEvent() throws {
        let data = Data(PermissionGrantEvent.json(transport: "ble").utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]]

        XCTAssertEqual(object, ["PermissionGranted": ["transport": "ble"]])
    }

    func testCoreAcceptsTheGrantFromTheShell() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try VauchiRepository(dataDir: dir.path)
        try repo.createIdentity(displayName: "Grant Test")

        let result = try repo.appEngine.dispatchJson(
            eventJson: PermissionGrantEvent.json(transport: CameraService.transport)
        )

        let envelope = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertNotNil(envelope?["commands"] as? [Any], "Core must answer the grant with a command batch")
    }

    func testBluetoothReportsAGrantOnlyWhenAPromptWasPending() {
        XCTAssertTrue(BleExchangeService.reportsGrant(authorizationWasPending: true, state: .poweredOn))
        XCTAssertFalse(BleExchangeService.reportsGrant(authorizationWasPending: false, state: .poweredOn))
        XCTAssertFalse(BleExchangeService.reportsGrant(authorizationWasPending: true, state: .unauthorized))
    }
}
