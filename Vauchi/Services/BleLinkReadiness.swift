// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import VauchiPlatform

/// What a central's subscription tells Core. A central subscribed to
/// `dataNotify` can receive frames from then on; a frame sent earlier is lost
/// to the 5 s retry of Core's sender. iOS gives no MTU callback, so the
/// subscription is also where the MTU becomes known, and it must reach Core
/// before readiness starts the first frame.
enum BleLinkReadiness {
    private static let attNotificationHeaderBytes = 3

    static func events(
        subscribedTo characteristicUuid: String,
        deviceId: String,
        maximumUpdateValueLength: Int
    ) -> [MobileEvent] {
        guard characteristicUuid.lowercased() == BleUuids.dataNotify else { return [] }
        return [
            .bleMtuNegotiated(
                deviceId: deviceId,
                mtu: UInt32(max(0, maximumUpdateValueLength) + attNotificationHeaderBytes)
            ),
            .bleGattReady(deviceId: deviceId),
        ]
    }
}
