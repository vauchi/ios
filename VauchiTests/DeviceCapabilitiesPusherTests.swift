// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeviceCapabilitiesPusherTests.swift
// Pins the JSON wire shape that `DeviceCapabilitiesPusher` sends to
// core's `setDeviceCapabilitiesJson`. The string must deserialize into
// core's `DeviceCapabilities` (serde, snake_case keys, bare-string
// enum variants), so these tests assert the exact serialized form —
// a silent key/casing drift here would re-introduce the all-false
// `DeviceCapabilities::default()` bug that
// `2026-05-23-exchange-capabilities-frontend-gap` was filed for.
//
// Hardware detection (`detectDeviceHardware`) is not unit-tested: it
// reads simulator/device hardware and has no deterministic output.
// The contract that matters — the wire shape — lives in the pure
// `buildDeviceCapabilitiesJson` builder, which is fully covered here.

@testable import Vauchi
import XCTest

final class DeviceCapabilitiesPusherTests: XCTestCase {
    /// Parse the builder output back into a dictionary so assertions do
    /// not depend on key ordering.
    private func parse(_ json: String) -> [String: Any] {
        let data = Data(json.utf8)
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any]
        else {
            XCTFail("builder produced invalid JSON: \(json)")
            return [:]
        }
        return dict
    }

    /// A fully-capable phone: Face ID, camera, NFC, accelerometer.
    func test_full_capability_phone_serializes_every_field() {
        let hw = DeviceHardware(
            hasNfc: true,
            hasBle: true,
            hasCamera: true,
            audio: .full,
            hasBiometrics: true,
            biometricType: .faceId,
            hasSecureEnclave: true,
            hasAccelerometer: true,
            hasInternet: true,
            hasUsbPort: false
        )

        let dict = parse(buildDeviceCapabilitiesJson(hw))

        XCTAssertEqual(dict["has_nfc"] as? Bool, true)
        XCTAssertEqual(dict["has_ble"] as? Bool, true)
        XCTAssertEqual(dict["has_camera"] as? Bool, true)
        XCTAssertEqual(dict["audio"] as? String, "Full")
        XCTAssertEqual(dict["has_biometrics"] as? Bool, true)
        XCTAssertEqual(dict["biometric_type"] as? String, "FaceId")
        XCTAssertEqual(dict["has_secure_enclave"] as? Bool, true)
        XCTAssertEqual(dict["platform"] as? String, "Ios")
        XCTAssertEqual(dict["has_accelerometer"] as? Bool, true)
        XCTAssertEqual(dict["has_internet"] as? Bool, true)
        XCTAssertEqual(dict["has_usb_port"] as? Bool, false)
    }

    /// Touch ID maps to the `Fingerprint` core variant.
    func test_touch_id_maps_to_fingerprint() {
        let hw = DeviceHardware(
            hasNfc: false,
            hasBle: true,
            hasCamera: true,
            audio: .full,
            hasBiometrics: true,
            biometricType: .fingerprint,
            hasSecureEnclave: true,
            hasAccelerometer: true,
            hasInternet: true,
            hasUsbPort: false
        )

        let dict = parse(buildDeviceCapabilitiesJson(hw))

        XCTAssertEqual(dict["biometric_type"] as? String, "Fingerprint")
        XCTAssertEqual(dict["has_nfc"] as? Bool, false)
    }

    /// No biometrics → `biometric_type` is JSON null, not omitted, and
    /// `has_biometrics` is false. Verifies the null branch explicitly.
    func test_no_biometrics_emits_null_biometric_type() {
        let hw = DeviceHardware(
            hasNfc: false,
            hasBle: true,
            hasCamera: false,
            audio: .none,
            hasBiometrics: false,
            biometricType: nil,
            hasSecureEnclave: true,
            hasAccelerometer: false,
            hasInternet: true,
            hasUsbPort: false
        )

        let json = buildDeviceCapabilitiesJson(hw)
        let dict = parse(json)

        XCTAssertTrue(
            json.contains("\"biometric_type\":null"),
            "nil biometricType must serialize as JSON null, got: \(json)"
        )
        // JSON `null` decodes to NSNull (key present, value null) — this
        // is exactly what serde's `Option<BiometricType>` accepts for the
        // `None` case. Verify it is present-as-null, not absent.
        XCTAssertTrue(
            dict["biometric_type"] is NSNull,
            "biometric_type must be present as JSON null"
        )
        XCTAssertEqual(dict["has_biometrics"] as? Bool, false)
        XCTAssertEqual(dict["audio"] as? String, "None")
        XCTAssertEqual(dict["has_camera"] as? Bool, false)
    }

    /// Every `DeviceAudioCapability` rawValue matches a core variant.
    func test_audio_capability_raw_values_match_core_variants() {
        XCTAssertEqual(DeviceAudioCapability.full.rawValue, "Full")
        XCTAssertEqual(DeviceAudioCapability.emitOnly.rawValue, "EmitOnly")
        XCTAssertEqual(DeviceAudioCapability.receiveOnly.rawValue, "ReceiveOnly")
        XCTAssertEqual(DeviceAudioCapability.none.rawValue, "None")
    }

    /// `.opticID` and `.none` have no core equivalent → nil.
    func test_unsupported_biometry_types_map_to_nil() {
        XCTAssertNil(mapBiometryType(.none))
        if #available(iOS 17.0, *) {
            XCTAssertNil(mapBiometryType(.opticID))
        }
        XCTAssertEqual(mapBiometryType(.faceID), .faceId)
        XCTAssertEqual(mapBiometryType(.touchID), .fingerprint)
    }
}
