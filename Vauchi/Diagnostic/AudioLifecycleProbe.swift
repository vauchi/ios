// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import Foundation

    struct AudioProbeOutcome {
        var error = ""
        var samples: Int?
    }

    struct AudioProbeReport {
        let status: String
        let initialActive: Bool
        let actionReturnMs: Double?
        let workerReturnAfterActionMs: Double?
        let backendCallOverlap: Bool?
        let activeWhenOldReturned: Bool?
        let replacementPendingWhenOldReturned: Bool?
        let firstError: String?
        let secondError: String?
        let samples: Int?
    }

    final class AudioLifecycleProbe {
        private struct Returned {
            let time: UInt64
            let outcome: AudioProbeOutcome
        }

        private final class Call {
            private let lock = NSLock()
            private var entered: UInt64?
            private var returned: Returned?

            func enter() {
                lock.lock()
                entered = DispatchTime.now().uptimeNanoseconds
                lock.unlock()
            }

            func finish(_ outcome: AudioProbeOutcome) {
                lock.lock()
                returned = Returned(time: DispatchTime.now().uptimeNanoseconds, outcome: outcome)
                lock.unlock()
            }

            func snapshot() -> (UInt64?, Returned?) {
                lock.lock()
                defer { lock.unlock() }
                return (entered, returned)
            }
        }

        private let operation: (UInt64) -> AudioProbeOutcome
        private let active: () -> Bool
        private let stop: () -> Void

        init(
            operation: @escaping (UInt64) -> AudioProbeOutcome,
            active: @escaping () -> Bool,
            stop: @escaping () -> Void
        ) {
            self.operation = operation
            self.active = active
            self.stop = stop
        }

        private func launch(_ duration: UInt64) -> Call {
            let call = Call()
            let run = operation
            Thread.detachNewThread {
                call.enter()
                call.finish(run(duration))
            }
            return call
        }

        private func waitUntil(_ timeoutMs: UInt64, ready: () -> Bool) {
            let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMs * 1_000_000
            while !ready(), DispatchTime.now().uptimeNanoseconds < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }

        func measure(replace: Bool, settleMs: UInt64 = 250, waitMs: UInt64 = 5000) -> AudioProbeReport {
            let first = launch(2000)
            waitUntil(waitMs) { self.active() || first.snapshot().1 != nil }
            waitUntil(settleMs) { first.snapshot().1 != nil }
            let initialActive = active() && first.snapshot().1 == nil
            let actionEntry = DispatchTime.now().uptimeNanoseconds
            var actionReturn: UInt64?
            var second: Call?
            var activeAtOldReturn: Bool?
            var secondPending: Bool?
            var firstObserved: Returned?
            var secondObserved: Returned?
            defer { stop() }
            if initialActive {
                if replace {
                    second = launch(3000)
                } else {
                    stop()
                    actionReturn = DispatchTime.now().uptimeNanoseconds
                }
                waitUntil(waitMs) { first.snapshot().1 != nil }
                firstObserved = first.snapshot().1
                if replace, firstObserved != nil {
                    activeAtOldReturn = active()
                    secondPending = second?.snapshot().1 == nil
                }
                if let second {
                    waitUntil(waitMs) { second.snapshot().1 != nil }
                    secondObserved = second.snapshot().1
                }
            } else {
                firstObserved = first.snapshot().1
            }
            let overlap = second?.snapshot().0.map { entered in
                firstObserved.map { entered < $0.time } ?? true
            }
            let observed = initialActive && firstObserved != nil &&
                firstObserved?.outcome.error == "" &&
                (!replace || secondObserved?.outcome.error == "")
            return AudioProbeReport(
                status: observed ? "observed" : "inconclusive",
                initialActive: initialActive,
                actionReturnMs: actionReturn.map { milliseconds(actionEntry, $0) },
                workerReturnAfterActionMs: initialActive ? firstObserved.map { milliseconds(actionEntry, $0.time) } : nil,
                backendCallOverlap: overlap,
                activeWhenOldReturned: activeAtOldReturn,
                replacementPendingWhenOldReturned: secondPending,
                firstError: firstObserved?.outcome.error,
                secondError: secondObserved?.outcome.error,
                samples: firstObserved?.outcome.samples
            )
        }

        private func milliseconds(_ from: UInt64, _ to: UInt64) -> Double {
            Double(to >= from ? to - from : 0) / 1_000_000
        }
    }
#endif
