// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import VauchiPlatform
import XCTest

/// Pins the canonical event JSON the shell hands to `dispatchJson` for every
/// hardware observation (ADR-066: one Event input). The shapes mirror Core's
/// serde spelling — externally tagged variant, snake_case fields, bytes as
/// unsigned integer arrays — which `event_from_json` decodes. The same eight
/// cases are pinned by Android's `HardwareEventJsonTest`, so the shells
/// cannot drift from each other or from Core.
final class HardwareEventJsonTests: XCTestCase {
    func testBytePayloadsEncodeAsUnsignedIntegerArrays() {
        XCTAssertEqual(
            MobileEvent.nfcDataReceived(data: Data([0, 255, 16])).toEventJson(),
            #"{"NfcDataReceived":{"data":[0,255,16]}}"#
        )
    }

    func testUnitVariantsEncodeAsBareStrings() {
        XCTAssertEqual(MobileEvent.filePickCancelledByUser.toEventJson(), #""FilePickCancelledByUser""#)
        XCTAssertEqual(MobileEvent.imagePickCancelled.toEventJson(), #""ImagePickCancelled""#)
    }

    func testBleLinkDirectionEncodesAsCoreVariantName() {
        XCTAssertEqual(
            MobileEvent.bleConnected(deviceId: "dev-1", direction: .inbound).toEventJson(),
            #"{"BleConnected":{"device_id":"dev-1","direction":"Inbound"}}"#
        )
        XCTAssertEqual(
            MobileEvent.bleDeviceDiscovered(id: "dev-2", rssi: -70, advData: Data([1, 2])).toEventJson(),
            #"{"BleDeviceDiscovered":{"id":"dev-2","rssi":-70,"adv_data":[1,2]}}"#
        )
    }

    func testAbsentOptionalsEncodeAsNull() {
        XCTAssertEqual(
            MobileEvent.localNetworkAddressChanged(address: nil).toEventJson(),
            #"{"LocalNetworkAddressChanged":{"address":null}}"#
        )
        XCTAssertEqual(
            MobileEvent.locationResult(latitude: 47.5, longitude: 8.25, accuracyMeters: nil).toEventJson(),
            #"{"LocationResult":{"latitude":47.5,"longitude":8.25,"accuracy_meters":null}}"#
        )
    }

    func testStringsAreJsonEscaped() {
        XCTAssertEqual(
            MobileEvent.hardwareError(transport: "ble", error: "GATT \"133\"\nretry").toEventJson(),
            #"{"HardwareError":{"transport":"ble","error":"GATT \"133\"\nretry"}}"#
        )
    }

    func testAudioSamplesEncodeAsFloatArrayWithRate() {
        XCTAssertEqual(
            MobileEvent.audioSamplesRecorded(samples: [0.5, -1.0], sampleRate: 44100).toEventJson(),
            #"{"AudioSamplesRecorded":{"samples":[0.5,-1.0],"sample_rate":44100}}"#
        )
    }

    func testAccelerometerSampleEncodesUnsignedTimestamp() {
        XCTAssertEqual(
            MobileEvent.accelerometerData(timestampMs: 1, xMilliG: 2, yMilliG: -3, zMilliG: 4).toEventJson(),
            #"{"AccelerometerData":{"timestamp_ms":1,"x_milli_g":2,"y_milli_g":-3,"z_milli_g":4}}"#
        )
    }

    func testFilePickCarriesBytesThenFilename() {
        XCTAssertEqual(
            MobileEvent.filePickedFromUser(bytes: Data([7]), filename: "backup.vauchi").toEventJson(),
            #"{"FilePickedFromUser":{"bytes":[7],"filename":"backup.vauchi"}}"#
        )
    }

    /// A user-picked backup is far larger than any other observation; every
    /// byte value must survive the streaming encoder, in order, past the
    /// 64 KiB the pre-0.65 binding accepts.
    func testLargeBytePayloadStreamsEveryValueInOrder() {
        let payload = Data((0 ..< 70000).map { UInt8(truncatingIfNeeded: $0) })
        let expectedElements = (0 ..< 70000).map { String($0 % 256) }.joined(separator: ",")

        XCTAssertEqual(
            MobileEvent.imageReceived(data: payload).toEventJson(),
            #"{"ImageReceived":{"data":["# + expectedElements + "]}}"
        )
    }
}
