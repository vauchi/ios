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
    }
#endif
