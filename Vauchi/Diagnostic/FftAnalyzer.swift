// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import Foundation

enum FftAnalyzer {
    struct FrequencyBin {
        let frequencyHz: Int
        let magnitudeDb: Double
        let detected: Bool
    }

    static func goertzelMagnitudeDb(samples: [Float], targetFreqHz: Int, sampleRate: Int) -> Double {
        let n = samples.count
        let k = Int(0.5 + Double(n) * Double(targetFreqHz) / Double(sampleRate))
        let w = 2.0 * Double.pi * Double(k) / Double(n)
        let coeff = 2.0 * cos(w)
        var s1 = 0.0
        var s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        let magnitude = sqrt(abs(power)) / Double(n)
        return magnitude > 0 ? 20.0 * log10(magnitude) : -120.0
    }

    static func computeSnrDb(
        samples: [Float], targetFreqHz: Int, sampleRate: Int,
        bandStartHz: Int = 16000, bandEndHz: Int = 22000, bandStepHz: Int = 100
    ) -> Double {
        let targetDb = goertzelMagnitudeDb(samples: samples, targetFreqHz: targetFreqHz, sampleRate: sampleRate)
        let noiseFreqs = stride(from: bandStartHz, through: bandEndHz, by: bandStepHz)
            .filter { abs($0 - targetFreqHz) > 200 }
        let noiseDb = noiseFreqs.map {
            goertzelMagnitudeDb(samples: samples, targetFreqHz: $0, sampleRate: sampleRate)
        }
        let avgNoise = noiseDb.isEmpty ? -120.0 : noiseDb.reduce(0, +) / Double(noiseDb.count)
        return targetDb - avgNoise
    }

    static func analyzeBand(
        samples: [Float], startHz: Int, endHz: Int, stepHz: Int,
        sampleRate: Int, snrThresholdDb: Double = 15.0
    ) -> [FrequencyBin] {
        stride(from: startHz, through: endHz, by: stepHz).map { freq in
            let mag = goertzelMagnitudeDb(samples: samples, targetFreqHz: freq, sampleRate: sampleRate)
            let snr = computeSnrDb(samples: samples, targetFreqHz: freq, sampleRate: sampleRate,
                                   bandStartHz: startHz, bandEndHz: endHz, bandStepHz: stepHz)
            return FrequencyBin(frequencyHz: freq, magnitudeDb: mag, detected: snr >= snrThresholdDb)
        }
    }
}
