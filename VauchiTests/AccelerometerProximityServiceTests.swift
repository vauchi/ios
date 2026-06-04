// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Unit tests for the pure g → milli-g conversion the service applies to raw
/// `CMAccelerometerData` before handing readings to core. The CoreMotion
/// wiring (start/stop streaming) is framework glue; the conversion is the
/// load-bearing logic and must match core's envelope shape (1 g = 1000
/// milli-g, clamped at 8 g) and the Android `axisToMilliG`.
final class AccelerometerProximityServiceTests: XCTestCase {
    func testOneGConvertsTo1000MilliG() {
        XCTAssertEqual(AccelerometerProximityService.milliG(1.0), 1000)
    }

    func testZeroConvertsToZeroMilliG() {
        XCTAssertEqual(AccelerometerProximityService.milliG(0.0), 0)
    }

    func testHalfGConvertsTo500MilliG() {
        XCTAssertEqual(AccelerometerProximityService.milliG(0.5), 500)
    }

    func testTwoGConvertsTo2000MilliG() {
        XCTAssertEqual(AccelerometerProximityService.milliG(2.0), 2000)
    }

    func testNegativeGConvertsToNegativeMilliG() {
        XCTAssertEqual(AccelerometerProximityService.milliG(-1.0), -1000)
    }
}
