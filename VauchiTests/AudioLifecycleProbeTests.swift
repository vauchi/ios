// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

final class AudioLifecycleProbeTests: XCTestCase {
    func testNativeFailureIsInconclusive() {
        let probe = AudioLifecycleProbe(
            operation: { _ in AudioProbeOutcome(error: "device refused") },
            active: { false },
            stop: {}
        )
        let result = probe.measure(replace: false, settleMs: 0, waitMs: 500)
        XCTAssertEqual(result.status, "inconclusive")
        XCTAssertEqual(result.firstError, "device refused")
        XCTAssertNil(result.workerReturnAfterActionMs)
    }

    func testStopObservesWorkerReturn() {
        let backend = CooperativeAudio()
        let probe = AudioLifecycleProbe(
            operation: { _ in backend.run() },
            active: backend.active,
            stop: backend.stop
        )
        let result = probe.measure(replace: false, settleMs: 0, waitMs: 2000)
        XCTAssertEqual(result.status, "observed")
        XCTAssertTrue(result.initialActive)
        XCTAssertGreaterThanOrEqual(result.workerReturnAfterActionMs ?? -1, 0)
        XCTAssertLessThan(result.workerReturnAfterActionMs ?? 2000, 2000)
        XCTAssertEqual(result.samples, 32)
        XCTAssertEqual(result.firstError, "")
    }
}

private final class CooperativeAudio {
    private let condition = NSCondition()
    private var running = false
    private var stopped = false

    func run() -> AudioProbeOutcome {
        condition.lock()
        running = true
        while !stopped {
            condition.wait()
        }
        condition.unlock()
        return AudioProbeOutcome(samples: 32)
    }

    func active() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return running
    }

    func stop() {
        condition.lock()
        stopped = true
        running = false
        condition.broadcast()
        condition.unlock()
    }
}
