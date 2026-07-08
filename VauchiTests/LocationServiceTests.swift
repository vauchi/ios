// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for LocationService outcome mapping — capture-at-exchange (ADR-051).
// Based on: features/contact_exchange.feature - "where we met" annotation.

import CoreLocation
@testable import Vauchi
import VauchiHardware
import VauchiPlatform
import XCTest

/// Exercises the pure mapping seam (`decision(for:)`, `resultEvent(...)`) that
/// turns CoreLocation inputs into the `MobileEvent` reply, without driving a
/// live `CLLocationManager` (CC-23: the OS permission/fix flow is OS-tested).
final class LocationServiceTests: XCTestCase {
    // MARK: - Authorization decision

    func testAuthorizedWhenInUseRequestsFix() {
        XCTAssertEqual(
            LocationService.decision(for: .authorizedWhenInUse),
            .requestFix
        )
    }

    func testAuthorizedAlwaysRequestsFix() {
        XCTAssertEqual(
            LocationService.decision(for: .authorizedAlways),
            .requestFix
        )
    }

    func testDeniedFinishesWithPermissionDenied() {
        XCTAssertEqual(
            LocationService.decision(for: .denied),
            .finish(.permissionDenied(transport: "location"))
        )
    }

    func testRestrictedFinishesWithPermissionDenied() {
        XCTAssertEqual(
            LocationService.decision(for: .restricted),
            .finish(.permissionDenied(transport: "location"))
        )
    }

    func testNotDeterminedAwaitsCallback() {
        XCTAssertEqual(
            LocationService.decision(for: .notDetermined),
            .awaitCallback
        )
    }

    // MARK: - Result event mapping

    func testValidFixMapsCoordinatesAndAccuracy() {
        let event = LocationService.resultEvent(
            latitude: 47.3769,
            longitude: 8.5417,
            horizontalAccuracy: 12.5
        )
        XCTAssertEqual(
            event,
            .locationResult(latitude: 47.3769, longitude: 8.5417, accuracyMeters: 12.5)
        )
    }

    func testNegativeAccuracyMapsToNil() {
        let event = LocationService.resultEvent(
            latitude: 47.3769,
            longitude: 8.5417,
            horizontalAccuracy: -1
        )
        XCTAssertEqual(
            event,
            .locationResult(latitude: 47.3769, longitude: 8.5417, accuracyMeters: nil)
        )
    }

    func testZeroAccuracyIsKept() {
        let event = LocationService.resultEvent(
            latitude: 0,
            longitude: 0,
            horizontalAccuracy: 0
        )
        XCTAssertEqual(
            event,
            .locationResult(latitude: 0, longitude: 0, accuracyMeters: 0)
        )
    }
}
