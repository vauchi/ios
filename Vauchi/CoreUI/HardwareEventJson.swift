// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import VauchiPlatform

/// Encode a typed hardware observation as the canonical event JSON Core
/// decodes in `dispatchJson` (ADR-066: one Event input for every shell
/// observation). The spelling mirrors Core's serde contract: an externally
/// tagged variant, snake_case fields, bytes as unsigned integer arrays.
///
/// Duplicated verbatim in the iOS and macOS shells (and mirrored by
/// Android's `HardwareEventJson.kt`) rather than added to
/// `vauchi-platform-swift`, so the binding package stays generated-only.
extension MobileEvent {
    /// The only exhaustive switch: it routes each variant to its family so
    /// the per-family encoders can stay under the lint complexity budget.
    func toEventJson() -> String {
        switch self {
        case .bleDeviceDiscovered, .bleConnected, .bleCharacteristicRead, .bleCharacteristicNotified,
             .bleDisconnected:
            bleEventJson()
        case .qrScanned, .localNetworkAddressChanged, .nfcDataReceived, .audioSamplesRecorded,
             .accelerometerData, .impactDetected, .locationResult:
            sensorEventJson()
        case .relayEscrowReady, .relayEscrowBlobReceived, .relayEscrowFailed, .linkShared, .linkOpened,
             .directPayloadReceived, .directCardReceived:
            exchangeTransportEventJson()
        case .imageReceived, .imagePickCancelled, .filePickedFromUser, .filePickCancelledByUser,
             .biometricUnlockSucceeded, .hardwareError, .hardwareUnavailable, .permissionDenied:
            userAndPlatformEventJson()
        }
    }

    private func bleEventJson() -> String {
        switch self {
        case let .bleDeviceDiscovered(id, rssi, advData):
            variant("BleDeviceDiscovered", ("id", string(id)), ("rssi", String(rssi)), ("adv_data", bytes(advData)))
        case let .bleConnected(deviceId, direction):
            variant("BleConnected", ("device_id", string(deviceId)), ("direction", direction.eventJson))
        case let .bleCharacteristicRead(deviceId, direction, uuid, data):
            variant(
                "BleCharacteristicRead",
                ("device_id", string(deviceId)),
                ("direction", direction.eventJson),
                ("uuid", string(uuid)),
                ("data", bytes(data))
            )
        case let .bleCharacteristicNotified(deviceId, direction, uuid, data):
            variant(
                "BleCharacteristicNotified",
                ("device_id", string(deviceId)),
                ("direction", direction.eventJson),
                ("uuid", string(uuid)),
                ("data", bytes(data))
            )
        case let .bleDisconnected(deviceId, direction, reason):
            variant(
                "BleDisconnected",
                ("device_id", string(deviceId)),
                ("direction", direction.eventJson),
                ("reason", string(reason))
            )
        default:
            notInFamily("BLE")
        }
    }

    private func sensorEventJson() -> String {
        switch self {
        case let .qrScanned(data):
            variant("QrScanned", ("data", string(data)))
        case let .localNetworkAddressChanged(address):
            variant("LocalNetworkAddressChanged", ("address", nullable(address, string)))
        case let .nfcDataReceived(data):
            variant("NfcDataReceived", ("data", bytes(data)))
        case let .audioSamplesRecorded(samples, sampleRate):
            variant("AudioSamplesRecorded", ("samples", floats(samples)), ("sample_rate", String(sampleRate)))
        case let .accelerometerData(timestampMs, xMilliG, yMilliG, zMilliG):
            variant(
                "AccelerometerData",
                ("timestamp_ms", String(timestampMs)),
                ("x_milli_g", String(xMilliG)),
                ("y_milli_g", String(yMilliG)),
                ("z_milli_g", String(zMilliG))
            )
        case let .impactDetected(timestampMs, magnitudeMilliG):
            variant(
                "ImpactDetected",
                ("timestamp_ms", String(timestampMs)),
                ("magnitude_milli_g", String(magnitudeMilliG))
            )
        case let .locationResult(latitude, longitude, accuracyMeters):
            variant(
                "LocationResult",
                ("latitude", String(latitude)),
                ("longitude", String(longitude)),
                ("accuracy_meters", nullable(accuracyMeters) { String($0) })
            )
        default:
            notInFamily("sensor")
        }
    }

    private func exchangeTransportEventJson() -> String {
        switch self {
        case let .relayEscrowReady(gateHash):
            variant("RelayEscrowReady", ("gate_hash", bytes(gateHash)))
        case let .relayEscrowBlobReceived(gateHash, blob):
            variant("RelayEscrowBlobReceived", ("gate_hash", bytes(gateHash)), ("blob", bytes(blob)))
        case let .relayEscrowFailed(gateHash, reason):
            variant("RelayEscrowFailed", ("gate_hash", bytes(gateHash)), ("reason", string(reason)))
        case .linkShared:
            unit("LinkShared")
        case let .linkOpened(peerPublicKey):
            variant("LinkOpened", ("peer_public_key", bytes(peerPublicKey)))
        case let .directPayloadReceived(data):
            variant("DirectPayloadReceived", ("data", bytes(data)))
        case let .directCardReceived(ciphertext):
            variant("DirectCardReceived", ("ciphertext", bytes(ciphertext)))
        default:
            notInFamily("exchange transport")
        }
    }

    private func userAndPlatformEventJson() -> String {
        switch self {
        case let .imageReceived(data):
            variant("ImageReceived", ("data", bytes(data)))
        case .imagePickCancelled:
            unit("ImagePickCancelled")
        case let .filePickedFromUser(fileBytes, filename):
            variant("FilePickedFromUser", ("bytes", bytes(fileBytes)), ("filename", string(filename)))
        case .filePickCancelledByUser:
            unit("FilePickCancelledByUser")
        case .biometricUnlockSucceeded:
            unit("BiometricUnlockSucceeded")
        case let .hardwareError(transport, error):
            variant("HardwareError", ("transport", string(transport)), ("error", string(error)))
        case let .hardwareUnavailable(transport):
            variant("HardwareUnavailable", ("transport", string(transport)))
        case let .permissionDenied(transport):
            variant("PermissionDenied", ("transport", string(transport)))
        default:
            notInFamily("user/platform")
        }
    }

    /// Unreachable: `toEventJson` is exhaustive and routes every variant to
    /// exactly one family. Kept loud so a future variant added to only the
    /// router cannot silently encode as the wrong shape.
    private func notInFamily(_ family: String) -> Never {
        preconditionFailure("\(self) is not a \(family) event")
    }
}

private extension MobileBleLinkDirection {
    var eventJson: String {
        switch self {
        case .outbound: string("Outbound")
        case .inbound: string("Inbound")
        }
    }
}

private func unit(_ name: String) -> String {
    string(name)
}

/// Fields are pre-encoded JSON values, appended verbatim in the given order.
private func variant(_ name: String, _ fields: (key: String, value: String)...) -> String {
    var json = "{" + string(name) + ":{"
    for (index, field) in fields.enumerated() {
        if index > 0 { json += "," }
        json += string(field.key) + ":" + field.value
    }
    json += "}}"
    return json
}

private func nullable<T>(_ value: T?, _ encode: (T) -> String) -> String {
    value.map(encode) ?? "null"
}

private func floats(_ samples: [Float]) -> String {
    "[" + samples.map { String($0) }.joined(separator: ",") + "]"
}

/// Written straight into the string's own ASCII storage: a user-picked
/// backup can reach 32 MiB, and boxing that many elements through
/// `JSONSerialization` would multiply the allocation several times over.
private func bytes(_ data: Data) -> String {
    String(unsafeUninitializedCapacity: data.count * 4 + 2) { ascii in
        var length = 0
        func put(_ character: UInt8) {
            ascii[length] = character
            length += 1
        }
        put(UInt8(ascii: "["))
        for (index, byte) in data.enumerated() {
            if index > 0 { put(UInt8(ascii: ",")) }
            if byte >= 100 { put(UInt8(ascii: "0") + byte / 100) }
            if byte >= 10 { put(UInt8(ascii: "0") + (byte / 10) % 10) }
            put(UInt8(ascii: "0") + byte % 10)
        }
        put(UInt8(ascii: "]"))
        return length
    }
}

/// Escapes only what RFC 8259 requires — matching kotlinx.serialization on
/// Android, so identical observations produce identical JSON on every shell.
private func string(_ value: String) -> String {
    var json = "\""
    json.reserveCapacity(value.utf8.count + 2)
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"": json += "\\\""
        case "\\": json += "\\\\"
        case "\n": json += "\\n"
        case "\r": json += "\\r"
        case "\t": json += "\\t"
        case "\u{08}": json += "\\b"
        case "\u{0C}": json += "\\f"
        case ..<" ": json += String(format: "\\u%04x", scalar.value)
        default: json.unicodeScalars.append(scalar)
        }
    }
    return json + "\""
}
