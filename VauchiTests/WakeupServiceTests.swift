// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Tests for `WakeupService` scheduling and throttling (ADR-044 Am2a).
@MainActor
final class WakeupServiceTests: XCTestCase {
    override func tearDown() {
        WakeupService.shared.cancelPendingWakeup()
        super.tearDown()
    }

    func testScheduleWakeupFiresCallback() {
        let expectation = expectation(description: "wakeup fires")
        WakeupService.shared.setOnWakeup {
            expectation.fulfill()
        }

        WakeupService.shared.scheduleWakeup(
            earliestSecs: 0,
            deadlineSecs: 1,
            minIntervalSecs: 0
        )

        wait(for: [expectation], timeout: 1.5)
    }

    func testCancelPendingWakeupPreventsFire() {
        let expectation = expectation(description: "wakeup should not fire")
        expectation.isInverted = true
        WakeupService.shared.setOnWakeup {
            expectation.fulfill()
        }

        WakeupService.shared.scheduleWakeup(
            earliestSecs: 0,
            deadlineSecs: 1,
            minIntervalSecs: 0
        )
        WakeupService.shared.cancelPendingWakeup()

        wait(for: [expectation], timeout: 0.5)
    }
}
