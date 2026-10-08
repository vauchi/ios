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
            minIntervalSecs: 0,
            delayMillis: 0
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
            minIntervalSecs: 0,
            delayMillis: 0
        )
        WakeupService.shared.cancelPendingWakeup()

        wait(for: [expectation], timeout: 0.5)
    }

    func testASubSecondWakeupIsNotStretchedToTheWholeSecondMinimum() {
        // Core's terms for a live exchange: the frame dwell in milliseconds,
        // with one second in every whole-second field.
        let delay = WakeupService.fireDelay(
            deadlineSecs: 1,
            minIntervalSecs: 1,
            earliestMillis: 100,
            delayMillis: 100,
            sinceLastWakeup: 0.002
        )

        XCTAssertEqual(delay, 0.1, accuracy: 0.0001)
    }

    func testAWholeSecondWakeupWaitsOutTheMinimumInterval() {
        let delay = WakeupService.fireDelay(
            deadlineSecs: 90,
            minIntervalSecs: 30,
            earliestMillis: nil,
            delayMillis: 10000,
            sinceLastWakeup: 5
        )

        XCTAssertEqual(delay, 25, accuracy: 0.0001)
    }

    func testAWakeupNeverWaitsPastTheDeadline() {
        let delay = WakeupService.fireDelay(
            deadlineSecs: 10,
            minIntervalSecs: 0,
            earliestMillis: nil,
            delayMillis: 10000,
            sinceLastWakeup: nil
        )

        XCTAssertEqual(delay, 10, accuracy: 0.0001)
    }

    /// Core computes the wait and sends it as `delay_millis`; iOS starts
    /// from it instead of deriving its own, keeping only its min-interval
    /// guard and the deadline cap (vauchi/private#548).
    func testTheWaitStartsFromCoresDelay() {
        let delay = WakeupService.fireDelay(
            deadlineSecs: 90,
            minIntervalSecs: 0,
            earliestMillis: nil,
            delayMillis: 2000,
            sinceLastWakeup: nil
        )

        XCTAssertEqual(delay, 2, accuracy: 0.0001)
    }
}
