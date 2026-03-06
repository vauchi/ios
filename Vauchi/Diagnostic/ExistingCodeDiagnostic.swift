// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation

class ExistingCodeDiagnostic {
    private let audioService = AudioProximityService.shared
    private let sampleRate = 44100
    private let testFrequencies = [18500, 19500, 20500, 21000]

    func runLoopbackTest(log: @escaping (String) -> Void) {
        log("--- Test A: Loopback (existing code) ---")
        let capability = audioService.checkCapability()
        log("Capability: \(capability)")
        DiagnosticLogger.logResult(test: "A", track: "existing", message: "capability=\(capability)")

        for freq in testFrequencies {
            log("Testing \(freq) Hz via AudioProximityService...")

            let numSamples = (sampleRate * 3000) / 1000
            let angularFreq = 2.0 * Double.pi * Double(freq) / Double(sampleRate)
            let samples = (0 ..< numSamples).map { Float(sin(angularFreq * Double($0))) }

            let emitResult = audioService.emitSignal(samples: samples, sampleRate: UInt32(sampleRate))
            if !emitResult.isEmpty {
                DiagnosticLogger.logError(test: "A", track: "existing", error: "Emit failed at \(freq) Hz: \(emitResult)")
                log("  FAIL: emit error: \(emitResult)")
                continue
            }

            let recorded = audioService.receiveSignal(timeoutMs: 4000, sampleRate: UInt32(sampleRate))
            if recorded.isEmpty {
                DiagnosticLogger.logError(test: "A", track: "existing", error: "No samples at \(freq) Hz")
                log("  FAIL: no samples recorded")
                continue
            }

            let snr = FftAnalyzer.computeSnrDb(samples: recorded, targetFreqHz: freq, sampleRate: sampleRate)
            let mag = FftAnalyzer.goertzelMagnitudeDb(samples: recorded, targetFreqHz: freq, sampleRate: sampleRate)
            let detected = snr >= 15.0

            DiagnosticLogger.logResult(test: "A", track: "existing",
                                       frequencyHz: freq, snrDb: snr, magnitudeDb: mag, detected: detected)
            log("  \(freq)Hz: SNR=\(String(format: "%.1f", snr))dB \(detected ? "PASS" : "FAIL")")
        }
    }

    func runNoiseFloorTest(log: @escaping (String) -> Void) {
        log("--- Test B: Noise Floor (existing code) ---")

        let recorded = audioService.receiveSignal(timeoutMs: 5000, sampleRate: UInt32(sampleRate))
        if recorded.isEmpty {
            log("FAIL: no samples recorded")
            return
        }

        let bins = FftAnalyzer.analyzeBand(samples: recorded, startHz: 16000, endHz: 22000,
                                           stepHz: 100, sampleRate: sampleRate)
        let maxBin = bins.max(by: { $0.magnitudeDb < $1.magnitudeDb })
        let pass = bins.allSatisfy { $0.magnitudeDb < -30.0 }

        for bin in bins {
            DiagnosticLogger.logResult(test: "B", track: "existing",
                                       frequencyHz: bin.frequencyHz, magnitudeDb: bin.magnitudeDb)
        }

        log("Max: \(maxBin?.frequencyHz ?? 0)Hz at \(String(format: "%.1f", maxBin?.magnitudeDb ?? 0))dBFS")
        log("Result: \(pass ? "PASS" : "FAIL")")
    }
}
#endif
