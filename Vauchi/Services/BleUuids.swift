// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreBluetooth
import Foundation

/// GATT service + characteristic UUIDs for the vauchi BLE exchange, mirroring
/// `core/vauchi-core/src/exchange/ble.rs` and the Android `BleUuids.kt`. The
/// peripheral's GATT server exposes all of these; the central writes to the
/// WRITE characteristics and subscribes to the NOTIFY ones. Core addresses them
/// by UUID in the BLE commands, so the bridge stays generic.
enum BleUuids {
    static let service = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    /// Read + Notify — exchange payload (legacy).
    static let exchangePayload = "a1b2c3d4-e5f6-7890-abcd-ef1234567891"
    /// Write + Notify — card exchange (legacy).
    static let cardExchange = "a1b2c3d4-e5f6-7890-abcd-ef1234567892"
    /// Write + Notify — challenge-response (legacy).
    static let challenge = "a1b2c3d4-e5f6-7890-abcd-ef1234567893"
    /// Write (with response) — initiator → responder handshake.
    static let handshakeWrite = "a1b2c3d4-e5f6-7890-abcd-ef1234567894"
    /// Notify — responder → initiator handshake.
    static let handshakeNotify = "a1b2c3d4-e5f6-7890-abcd-ef1234567895"
    /// Write (no response) — initiator → responder data chunks.
    static let dataWrite = "a1b2c3d4-e5f6-7890-abcd-ef1234567896"
    /// Notify — responder → initiator data chunks.
    static let dataNotify = "a1b2c3d4-e5f6-7890-abcd-ef1234567897"

    /// All exchange characteristics the peripheral's GATT server exposes.
    static let allCharacteristics: [String] = [
        exchangePayload, cardExchange, challenge,
        handshakeWrite, handshakeNotify, dataWrite, dataNotify,
    ]

    /// Characteristics that support notifications (NOTIFY property).
    static let notifyCharacteristics: Set<String> = [
        exchangePayload, cardExchange, challenge, handshakeNotify, dataNotify,
    ]

    /// Write characteristics that use Write-With-Response (vs no-response).
    static let writeWithResponse: Set<String> = [cardExchange, challenge, handshakeWrite]

    /// A characteristic the responder (peripheral) pushes on — a
    /// `BleWriteCharacteristic` for one of these is a peripheral notify, not a
    /// central GATT write (matches Android `BleUuids.peripheralNotifyChars`).
    static let peripheralNotifyChars: Set<String> = [handshakeNotify, dataNotify]

    // MARK: - Role-tiebreak token <-> 32-bit service UUID (P5c)

    /// Token bytes carried in the advertisement. Core's identity-derived
    /// tiebreak token (ADR-043) rides as a 32-bit Bluetooth-base service UUID
    /// alongside the 128-bit service UUID — the only portable channel, since
    /// iOS can't advertise service/manufacturer data (only service UUIDs). The
    /// 32-bit UUID is a `CBUUID` built from 4 bytes; the peer reads it back the
    /// same way. See `2026-06-07-ios-ble-execution-parity-plan`.
    static let advTokenBytes = 4

    /// Encode the first `advTokenBytes` of `token` as a 32-bit service `CBUUID`
    /// for advertising. `CBUUID(data:)` with 4 bytes yields a 32-bit UUID,
    /// matching Android's `tokenToServiceUuid` (same big-endian 4 bytes).
    static func tokenToServiceUUID(_ token: Data) -> CBUUID {
        var bytes = [UInt8](token.prefix(advTokenBytes))
        while bytes.count < advTokenBytes {
            bytes.append(0)
        }
        return CBUUID(data: Data(bytes))
    }

    /// Decode a scanned service `CBUUID` back to its token bytes, or `nil` if it
    /// is not a 32-bit UUID (e.g. the 128-bit service UUID reports 16 bytes).
    /// The central picks the token UUID out of the advertised service-UUID list.
    static func tokenFromServiceUUID(_ uuid: CBUUID) -> Data? {
        uuid.data.count == advTokenBytes ? uuid.data : nil
    }
}
