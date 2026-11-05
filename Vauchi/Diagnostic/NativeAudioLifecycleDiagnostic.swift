// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import Foundation

    enum NativeAudioLifecycleDiagnostic {
        static func run(_ name: String, log: @escaping (String) -> Void) {
            let recording = name.contains("record")
            let service = AudioProximityService.shared
            service.stop()
            DiagnosticLogger.logResult(test: name, track: "lifecycle", message: "START silence=true samples_saved=false")
            if name.contains("callback") {
                let message = callbackReport(name, service: service)
                log(message)
                DiagnosticLogger.logResult(test: name, track: "lifecycle", message: message)
                return
            }
            let probe = AudioLifecycleProbe(
                operation: { duration in
                    if recording {
                        let count = service.receiveSignalSync(timeoutMs: duration, sampleRate: 44100).count
                        return AudioProbeOutcome(samples: count)
                    }
                    let samples = [Float](repeating: 0, count: Int(duration * 44100 / 1000))
                    return AudioProbeOutcome(error: service.emitSignal(samples: samples, sampleRate: 44100))
                },
                active: service.isActive,
                stop: service.stop
            )
            let result = probe.measure(replace: name.hasSuffix("replace"))
            let message = String(describing: result)
            log("\(name) \(message)")
            DiagnosticLogger.logResult(test: name, track: "lifecycle", message: message)
        }

        private static func callbackReport(_ name: String, service: AudioProximityService) -> String {
            defer { service.stop() }
            let lock = NSLock()
            let returned = DispatchSemaphore(value: 0)
            var cancelledCallback = false
            var replacementSamples = -1
            var playbackError = ""
            func launch(_ duration: UInt64, completion: @escaping (Int) -> Void) {
                if name.contains("record") {
                    service.receiveSignal(timeoutMs: duration, sampleRate: 44100) { samples, _ in completion(samples.count) }
                } else {
                    let samples = [Float](repeating: 0, count: Int(duration * 44100 / 1000))
                    service.emitSignal(samples: samples, sampleRate: 44100) { error in
                        lock.lock()
                        playbackError = error
                        lock.unlock()
                        completion(-1)
                    }
                }
            }
            launch(2000) { _ in
                lock.lock(); cancelledCallback = true; lock.unlock()
            }
            let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
            while !service.isActive(), DispatchTime.now().uptimeNanoseconds < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            let initiallyActive = service.isActive()
            Thread.sleep(forTimeInterval: 0.25)
            let replace = name.hasSuffix("replace")
            let actionTime = DispatchTime.now().uptimeNanoseconds
            if replace {
                launch(3000) { count in
                    lock.lock(); replacementSamples = count; lock.unlock()
                    returned.signal()
                }
            } else {
                service.stop()
            }
            let replacementDelivered = replace && returned.wait(timeout: .now() + 5) == .success
            if !replace {
                Thread.sleep(forTimeInterval: 2.2)
            }
            let windowMs = (DispatchTime.now().uptimeNanoseconds - actionTime) / 1_000_000
            lock.lock()
            defer { lock.unlock() }
            let observed = initiallyActive && !cancelledCallback && (!replace || replacementDelivered) && playbackError.isEmpty
            return "callback_status=\(observed ? "observed" : "inconclusive") initial_active=\(initiallyActive) " +
                "cancelled_callback_delivered=\(cancelledCallback) replacement_callback_delivered=\(replacementDelivered) " +
                "replacement_samples=\(replacementSamples) observation_window_ms=\(windowMs) error=\(playbackError)"
        }
    }
#endif
