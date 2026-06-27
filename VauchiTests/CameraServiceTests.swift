// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for CameraService outcome mapping — the exchange QR leg fails fast on a
// camera-permission denial instead of waiting forever (T0.5; mirrors
// LocationService / Android T0.3). CC-23: exercises only the pure decision fn,
// never a live AVCaptureDevice.

import AVFoundation
@testable import Vauchi
import VauchiPlatform
import XCTest

final class CameraServiceTests: XCTestCase {
    func testAuthorizedProceeds() {
        XCTAssertEqual(CameraService.decision(for: .authorized), .proceed)
    }

    func testDeniedFinishesWithPermissionDenied() {
        XCTAssertEqual(
            CameraService.decision(for: .denied),
            .finish(.permissionDenied(transport: "camera"))
        )
    }

    func testRestrictedFinishesWithPermissionDenied() {
        XCTAssertEqual(
            CameraService.decision(for: .restricted),
            .finish(.permissionDenied(transport: "camera"))
        )
    }

    func testNotDeterminedAwaitsCallback() {
        XCTAssertEqual(CameraService.decision(for: .notDetermined), .awaitCallback)
    }

    func testGrantedProceeds() {
        XCTAssertEqual(CameraService.decision(forGranted: true), .proceed)
    }

    func testNotGrantedFinishesWithPermissionDenied() {
        XCTAssertEqual(
            CameraService.decision(forGranted: false),
            .finish(.permissionDenied(transport: "camera"))
        )
    }

    // Contract-pin: the wire transport string is exactly "camera" (design §4).
    func testTransportStringIsCamera() {
        XCTAssertEqual(CameraService.transport, "camera")
    }

    /// Negative (CC-03): a grant must NOT be reported as a denial.
    func testAuthorizedIsNotADenial() {
        XCTAssertNotEqual(
            CameraService.decision(for: .authorized),
            .finish(.permissionDenied(transport: "camera"))
        )
    }
}
