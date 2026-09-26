// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// `--simulate-camera` lets the store-screenshot job reach Glance on the
// simulator, which reports no camera, so Core's exchange gate never offers
// the QR mode there. Only the reported capability changes; Core still
// decides which modes to offer.

@testable import Vauchi
import XCTest

final class DebugCapabilityOverrideTests: XCTestCase {
    private let simulator = DeviceHardware(
        hasNfc: false,
        hasBle: true,
        hasCamera: false,
        audio: .full,
        hasBiometrics: false,
        biometricType: nil,
        hasSecureEnclave: true,
        hasAccelerometer: false,
        hasInternet: true,
        hasUsbPort: false
    )

    func testSimulateCameraReportsACamera() {
        let hardware = applyDebugCapabilityOverrides(simulator, arguments: ["Vauchi", "--simulate-camera"])

        XCTAssertTrue(hardware.hasCamera)
    }

    func testWithoutTheArgumentTheDetectedCameraStands() {
        let hardware = applyDebugCapabilityOverrides(simulator, arguments: ["Vauchi", "--reset-for-testing"])

        XCTAssertFalse(hardware.hasCamera)
    }

    func testSimulateCameraChangesNothingElse() {
        let hardware = applyDebugCapabilityOverrides(simulator, arguments: ["Vauchi", "--simulate-camera"])

        XCTAssertEqual(buildDeviceCapabilitiesJson(hardware),
                       buildDeviceCapabilitiesJson(DeviceHardware(
                           hasNfc: false, hasBle: true, hasCamera: true, audio: .full,
                           hasBiometrics: false, biometricType: nil, hasSecureEnclave: true,
                           hasAccelerometer: false, hasInternet: true, hasUsbPort: false
                       )))
    }
}
