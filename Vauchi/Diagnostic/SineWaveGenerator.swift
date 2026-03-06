// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation

enum SineWaveGenerator {
    static func generate(frequencyHz: Int, durationMs: Int, sampleRate: Int = 44100) -> [Float] {
        let numSamples = (sampleRate * durationMs) / 1000
        let angularFreq = 2.0 * Double.pi * Double(frequencyHz) / Double(sampleRate)
        return (0 ..< numSamples).map { Float(sin(angularFreq * Double($0))) }
    }

    static func generateSweep(
        startHz: Int, endHz: Int, stepHz: Int,
        stepDurationMs: Int, sampleRate: Int = 44100
    ) -> ([Float], [(Int, Int)]) {
        let frequencies = stride(from: startHz, through: endHz, by: stepHz).map { $0 }
        let samplesPerStep = (sampleRate * stepDurationMs) / 1000
        var samples = [Float](repeating: 0, count: frequencies.count * samplesPerStep)
        var markers: [(Int, Int)] = []
        for (index, freq) in frequencies.enumerated() {
            let offset = index * samplesPerStep
            markers.append((freq, offset))
            let angularFreq = 2.0 * Double.pi * Double(freq) / Double(sampleRate)
            for i in 0 ..< samplesPerStep {
                samples[offset + i] = Float(sin(angularFreq * Double(i)))
            }
        }
        return (samples, markers)
    }
}
#endif
