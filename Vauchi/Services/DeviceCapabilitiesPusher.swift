// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeviceCapabilitiesPusher.swift
// Detects this device's exchange-relevant hardware and pushes it to
// core's `DeviceCapabilities` via `setDeviceCapabilitiesJson`. Mirrors
// `RenderContextPusher.swift`: a pure JSON builder + a thin
// side-effecting push that does the hardware queries.
//
// Closes the frontend half of `2026-05-23-exchange-capabilities-frontend-gap`:
// the 2026-04-01 exchange-modes-tier1 plan shipped the core surface
// (PAE `set_device_capabilities_json` → `AppEngine.device_capabilities`
// → `ExchangeConfig` → `ModeSelectionEngine`) but no frontend ever
// reported its hardware, so the Exchange screen rendered against
// `DeviceCapabilities::default()` (all-false). Without this push, the
// mode picker offers nothing the device can actually do.

import CoreMotion
import CoreNFC
import Foundation
import LocalAuthentication
import UIKit
import VauchiPlatform

/// Ultrasonic audio capability — `rawValue`s match core's
/// `AudioCapability` serde variant names (`core/vauchi-core/src/types.rs`).
enum DeviceAudioCapability: String {
    case full = "Full"
    case emitOnly = "EmitOnly"
    case receiveOnly = "ReceiveOnly"
    case none = "None"
}

/// Biometric hardware kind — `rawValue`s match core's `BiometricType`
/// serde variant names (`core/vauchi-core/src/exchange/capability/types.rs`).
enum DeviceBiometricType: String {
    case fingerprint = "Fingerprint"
    case faceId = "FaceId"
    case iris = "Iris"
}

/// Plain value type holding the detected hardware flags. Separated from
/// detection so the JSON serialization is unit-testable without a
/// device or simulator-hardware dependency.
struct DeviceHardware {
    var hasNfc: Bool
    var hasBle: Bool
    var hasCamera: Bool
    var audio: DeviceAudioCapability
    var hasBiometrics: Bool
    var biometricType: DeviceBiometricType?
    var hasSecureEnclave: Bool
    var hasAccelerometer: Bool
    var hasInternet: Bool
    var hasUsbPort: Bool
}

/// Build the JSON object core's `DeviceCapabilities` deserializes
/// (`serde`, snake_case, every field `#[serde(default)]`). `platform`
/// is always `"Ios"` from this pusher. Pure — no hardware access.
func buildDeviceCapabilitiesJson(_ hw: DeviceHardware) -> String {
    var parts: [String] = [
        "\"has_nfc\":\(jsonBool(hw.hasNfc))",
        "\"has_ble\":\(jsonBool(hw.hasBle))",
        "\"has_camera\":\(jsonBool(hw.hasCamera))",
        "\"audio\":\"\(hw.audio.rawValue)\"",
        "\"has_biometrics\":\(jsonBool(hw.hasBiometrics))",
    ]
    if let biometricType = hw.biometricType {
        parts.append("\"biometric_type\":\"\(biometricType.rawValue)\"")
    } else {
        parts.append("\"biometric_type\":null")
    }
    parts.append("\"has_secure_enclave\":\(jsonBool(hw.hasSecureEnclave))")
    parts.append("\"platform\":\"Ios\"")
    parts.append("\"has_accelerometer\":\(jsonBool(hw.hasAccelerometer))")
    parts.append("\"has_internet\":\(jsonBool(hw.hasInternet))")
    parts.append("\"has_usb_port\":\(jsonBool(hw.hasUsbPort))")
    return "{" + parts.joined(separator: ",") + "}"
}

private func jsonBool(_ value: Bool) -> String {
    value ? "true" : "false"
}

/// Query iOS hardware APIs for the exchange-relevant capabilities.
///
/// Conservative choices:
/// - `hasBle` / `hasSecureEnclave` / `hasInternet` are `true` for every
///   Vauchi-supported iPhone/iPad (all ship BLE, a Secure Enclave, and
///   networking). Querying BLE presence directly would instantiate a
///   `CBCentralManager` and trigger a permission prompt at boot — wrong
///   moment, and presence ≠ authorization.
/// - `hasUsbPort` is `false`: iOS sandboxing forbids the arbitrary USB
///   data exchange the Cable mode needs.
/// - `audio` is `.full`: every iOS device has a speaker and microphone.
func detectDeviceHardware() -> DeviceHardware {
    let laContext = LAContext()
    var laError: NSError?
    let hasBiometrics = laContext.canEvaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        error: &laError
    )
    // `biometryType` is only populated after `canEvaluatePolicy` runs.
    let biometricType: DeviceBiometricType? = hasBiometrics
        ? mapBiometryType(laContext.biometryType)
        : nil

    return DeviceHardware(
        hasNfc: NFCNDEFReaderSession.readingAvailable,
        hasBle: true,
        hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
        audio: .full,
        hasBiometrics: hasBiometrics,
        biometricType: biometricType,
        hasSecureEnclave: true,
        hasAccelerometer: CMMotionManager().isAccelerometerAvailable,
        hasInternet: true,
        hasUsbPort: false
    )
}

/// Map `LABiometryType` to core's biometric kind. `.opticID` (Vision
/// Pro) has no core equivalent and Vauchi does not ship there, so it
/// maps to `nil` alongside `.none`.
func mapBiometryType(_ type: LABiometryType) -> DeviceBiometricType? {
    switch type {
    case .faceID: .faceId
    case .touchID: .fingerprint
    default: nil
    }
}

/// Detect this device's hardware and push it to core's
/// `DeviceCapabilities`. Call once at boot, before the first navigation
/// to the Exchange screen. Idempotent at the core level — a later call
/// simply overwrites the stored capabilities.
func pushDeviceCapabilities(engine: PlatformAppEngine?) {
    guard let engine else { return }
    let json = buildDeviceCapabilitiesJson(detectDeviceHardware())
    do {
        try engine.setDeviceCapabilitiesJson(capabilitiesJson: json)
    } catch {
        NSLog("[DeviceCapabilitiesPusher] Failed: \(type(of: error))")
    }
}
