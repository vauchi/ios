// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import AVFoundation
    import SwiftUI

    struct DiagnosticView: View {
        /// Set to run a specific test on appear: "loopback", "noise", "sweep", "mode",
        /// "emit", "listen", "all"
        var autoTest: String?

        @State private var logLines: [String] = []
        @State private var running = false

        private let sampleRate: Int = 44100
        private let testFrequencies: [Int] = [18500, 19500, 20500, 21000]

        var body: some View {
            VStack(spacing: 16) {
                Text("Ultrasonic Diagnostic")
                    .font(Font.title2.weight(.bold))

                HStack(spacing: 12) {
                    diagButton("A: Loopback") { testLoopback() }
                    diagButton("B: Noise") { testNoiseFloor() }
                    diagButton("D: Sweep") { testSweep() }
                }

                HStack(spacing: 12) {
                    diagButton("E: Mode Cmp") { testModeComparison() }
                    diagButton("C: Listen") { testCrossDeviceListen() }
                    diagButton("C: Emit") { testCrossDeviceEmit() }
                }

                Divider()
                Text("Existing Code Track:").font(.caption).bold()
                HStack(spacing: 8) {
                    Button("A: Loopback (existing)") {
                        let diag = ExistingCodeDiagnostic()
                        runAsync { diag.runLoopbackTest(log: log) }
                    }.disabled(running)
                    Button("B: Noise (existing)") {
                        let diag = ExistingCodeDiagnostic()
                        runAsync { diag.runNoiseFloorTest(log: log) }
                    }.disabled(running)
                }

                NavigationLink("QR Camera Tuner") {
                    QrCameraTunerView(autoTest: nil)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

                if running {
                    ProgressView("Running...")
                        .padding(.vertical, 4)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onChange(of: logLines.count) { _ in
                        if let last = logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let test = autoTest {
                    runAsync { runAutoTest(test) }
                }
            }
        }

        // MARK: - Auto Test

        private func runAutoTest(_ test: String) {
            switch test {
            case "loopback": testLoopback()
            case "noise": testNoiseFloor()
            case "sweep": testSweep()
            case "mode": testModeComparison()
            case "emit": testCrossDeviceEmit()
            case "listen": testCrossDeviceListen()
            case "all":
                testLoopback()
                testNoiseFloor()
                testSweep()
                testModeComparison()
            default:
                log("Unknown test: \(test)")
            }
        }

        // MARK: - UI Helpers

        private func diagButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title) {
                runAsync(action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(running)
            .font(.caption)
        }

        private func runAsync(_ work: @escaping () -> Void) {
            DispatchQueue.main.async { running = true }
            DispatchQueue.global(qos: .userInitiated).async {
                work()
                DispatchQueue.main.async { running = false }
            }
        }

        private func log(_ msg: String) {
            let timestamped = "[\(timeStamp())] \(msg)"
            DispatchQueue.main.async {
                logLines.append(timestamped)
            }
        }

        private func timeStamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: Date())
        }

        // MARK: - Test A: Loopback

        private func testLoopback() {
            log("=== Test A: Loopback ===")
            for freq in testFrequencies {
                log("Testing \(freq) Hz...")
                guard let recorded = emitAndRecord(frequencyHz: freq, durationMs: 3000) else {
                    log("FAIL \(freq) Hz: no audio captured")
                    DiagnosticLogger.logError(test: "A_loopback", track: "single", error: "no audio at \(freq) Hz")
                    continue
                }
                let snr = FftAnalyzer.computeSnrDb(
                    samples: recorded, targetFreqHz: freq, sampleRate: sampleRate
                )
                let pass = snr >= 15.0
                log("\(freq) Hz: SNR=\(String(format: "%.1f", snr)) dB \(pass ? "PASS" : "FAIL")")
                DiagnosticLogger.logResult(
                    test: "A_loopback", track: "single",
                    frequencyHz: freq, snrDb: snr, detected: pass
                )
            }
            log("=== Test A complete ===")
        }

        // MARK: - Test B: Noise Floor

        private func testNoiseFloor() {
            log("=== Test B: Noise Floor ===")
            log("Recording 5s silence...")
            guard let recorded = recordOnly(durationMs: 5000) else {
                log("FAIL: no audio captured")
                DiagnosticLogger.logError(test: "B_noise", track: "single", error: "no audio captured")
                return
            }
            let bins = FftAnalyzer.analyzeBand(
                samples: recorded, startHz: 16000, endHz: 22000, stepHz: 100, sampleRate: sampleRate
            )
            let noisyBins = bins.filter { $0.magnitudeDb >= -30.0 }
            for bin in noisyBins {
                log("FAIL \(bin.frequencyHz) Hz: \(String(format: "%.1f", bin.magnitudeDb)) dBFS")
            }
            let allPass = noisyBins.isEmpty
            if allPass {
                log("PASS: all bins < -30 dBFS")
            }
            DiagnosticLogger.logResult(
                test: "B_noise", track: "single",
                detected: allPass, message: allPass ? "all bins clean" : "noise detected"
            )
            log("=== Test B complete ===")
        }

        // MARK: - Test C: Cross-Device

        private func testCrossDeviceEmit() {
            log("=== Test C: Emit ===")
            for freq in testFrequencies {
                log("Emitting \(freq) Hz for 3s...")
                emitOnly(frequencyHz: freq, durationMs: 3000)
                Thread.sleep(forTimeInterval: 0.5)
            }
            log("=== Test C Emit complete ===")
        }

        private func testCrossDeviceListen() {
            log("=== Test C: Listen ===")
            log("Recording 15s...")
            guard let recorded = recordOnly(durationMs: 15000) else {
                log("FAIL: no audio captured")
                DiagnosticLogger.logError(test: "C_listen", track: "single", error: "no audio captured")
                return
            }
            for freq in testFrequencies {
                let snr = FftAnalyzer.computeSnrDb(
                    samples: recorded, targetFreqHz: freq, sampleRate: sampleRate
                )
                let pass = snr >= 15.0
                log("\(freq) Hz: SNR=\(String(format: "%.1f", snr)) dB \(pass ? "DETECTED" : "NOT FOUND")")
                DiagnosticLogger.logResult(
                    test: "C_listen", track: "single",
                    frequencyHz: freq, snrDb: snr, detected: pass
                )
            }
            log("=== Test C Listen complete ===")
        }

        // MARK: - Test D: Frequency Sweep

        private func testSweep() {
            log("=== Test D: Frequency Sweep ===")
            let (sweepSamples, markers) = SineWaveGenerator.generateSweep(
                startHz: 16000, endHz: 22000, stepHz: 500, stepDurationMs: 200
            )
            log("Sweep: \(markers.count) steps, \(sweepSamples.count) samples")
            guard let recorded = emitAndRecordRaw(samples: sweepSamples, durationMs: markers.count * 200) else {
                log("FAIL: no audio captured")
                DiagnosticLogger.logError(test: "D_sweep", track: "single", error: "no audio captured")
                return
            }
            let samplesPerStep = (sampleRate * 200) / 1000
            for (freq, _) in markers {
                // Analyze the full recording for each frequency
                let segmentStart = max(0, (freq - 16000) / 500) * samplesPerStep
                let segmentEnd = min(recorded.count, segmentStart + samplesPerStep)
                guard segmentEnd > segmentStart else { continue }
                let segment = Array(recorded[segmentStart ..< segmentEnd])
                let snr = FftAnalyzer.computeSnrDb(
                    samples: segment, targetFreqHz: freq, sampleRate: sampleRate
                )
                let pass = snr >= 15.0
                log("\(freq) Hz: SNR=\(String(format: "%.1f", snr)) dB \(pass ? "PASS" : "FAIL")")
                DiagnosticLogger.logResult(
                    test: "D_sweep", track: "single",
                    frequencyHz: freq, snrDb: snr, detected: pass
                )
            }
            log("=== Test D complete ===")
        }

        // MARK: - Test E: Mode Comparison

        private func testModeComparison() {
            log("=== Test E: Mode Comparison ===")
            let freq = 19000

            // Test with .measurement mode
            log("Testing .measurement mode...")
            let snrMeasurement = runWithMode(.measurement, frequencyHz: freq)

            // Test with .voiceChat mode
            log("Testing .voiceChat mode...")
            let snrVoiceChat = runWithMode(.voiceChat, frequencyHz: freq)

            // Reset to measurement
            configureAudioSession(mode: .measurement)

            if let m = snrMeasurement, let v = snrVoiceChat {
                let diff = m - v
                log(".measurement SNR: \(String(format: "%.1f", m)) dB")
                log(".voiceChat SNR: \(String(format: "%.1f", v)) dB")
                log("Difference: \(String(format: "%.1f", diff)) dB (\(diff > 0 ? ".measurement wins" : ".voiceChat wins"))")
                DiagnosticLogger.logResult(
                    test: "E_mode_cmp", track: "measurement",
                    frequencyHz: freq, snrDb: m, audioMode: "measurement"
                )
                DiagnosticLogger.logResult(
                    test: "E_mode_cmp", track: "voiceChat",
                    frequencyHz: freq, snrDb: v, audioMode: "voiceChat"
                )
            } else {
                log("FAIL: could not complete mode comparison")
                DiagnosticLogger.logError(test: "E_mode_cmp", track: "single", error: "audio capture failed")
            }
            log("=== Test E complete ===")
        }

        private func runWithMode(_ mode: AVAudioSession.Mode, frequencyHz: Int) -> Double? {
            configureAudioSession(mode: mode)
            guard let recorded = emitAndRecord(frequencyHz: frequencyHz, durationMs: 3000) else {
                return nil
            }
            return FftAnalyzer.computeSnrDb(
                samples: recorded, targetFreqHz: frequencyHz, sampleRate: sampleRate
            )
        }

        // MARK: - Audio Helpers

        private func configureAudioSession(mode: AVAudioSession.Mode) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker])
                try session.setPreferredSampleRate(Double(sampleRate))
                try session.setActive(true)
            } catch {
                log("Audio session error: \(error.localizedDescription)")
            }
        }

        private func emitAndRecord(frequencyHz: Int, durationMs: Int) -> [Float]? {
            let samples = SineWaveGenerator.generate(
                frequencyHz: frequencyHz, durationMs: durationMs, sampleRate: sampleRate
            )
            return emitAndRecordRaw(samples: samples, durationMs: durationMs)
        }

        private func emitAndRecordRaw(samples: [Float], durationMs: Int) -> [Float]? {
            configureAudioSession(mode: .measurement)

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)

            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                channels: 1, interleaved: false
            )!
            engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
                log("Failed to create audio buffer")
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            let channelData = buffer.floatChannelData![0]
            for i in 0 ..< samples.count {
                channelData[i] = samples[i]
            }

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            var recordedSamples: [Float] = []
            let recordLock = NSLock()

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { tapBuffer, _ in
                guard let tapData = tapBuffer.floatChannelData?[0] else { return }
                let count = Int(tapBuffer.frameLength)
                let chunk = Array(UnsafeBufferPointer(start: tapData, count: count))
                recordLock.lock()
                recordedSamples.append(contentsOf: chunk)
                recordLock.unlock()
            }

            do {
                try engine.start()
            } catch {
                log("Engine start error: \(error.localizedDescription)")
                return nil
            }

            playerNode.play()
            playerNode.scheduleBuffer(buffer, completionHandler: nil)

            Thread.sleep(forTimeInterval: Double(durationMs) / 1000.0 + 0.5)

            inputNode.removeTap(onBus: 0)
            playerNode.stop()
            engine.stop()

            recordLock.lock()
            let result = recordedSamples
            recordLock.unlock()

            if result.isEmpty { return nil }

            // Resample if input format differs from target sample rate
            if Int(inputFormat.sampleRate) != sampleRate {
                return resample(result, from: Int(inputFormat.sampleRate), to: sampleRate)
            }
            return result
        }

        private func emitOnly(frequencyHz: Int, durationMs: Int) {
            configureAudioSession(mode: .measurement)

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)

            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                channels: 1, interleaved: false
            )!
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)

            let samples = SineWaveGenerator.generate(
                frequencyHz: frequencyHz, durationMs: durationMs, sampleRate: sampleRate
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                return
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            let channelData = buffer.floatChannelData![0]
            for i in 0 ..< samples.count {
                channelData[i] = samples[i]
            }

            do {
                try engine.start()
                playerNode.play()
                playerNode.scheduleBuffer(buffer, completionHandler: nil)
                Thread.sleep(forTimeInterval: Double(durationMs) / 1000.0 + 0.2)
                playerNode.stop()
                engine.stop()
            } catch {
                log("Emit error: \(error.localizedDescription)")
            }
        }

        private func recordOnly(durationMs: Int) -> [Float]? {
            configureAudioSession(mode: .measurement)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            var recordedSamples: [Float] = []
            let recordLock = NSLock()

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { tapBuffer, _ in
                guard let tapData = tapBuffer.floatChannelData?[0] else { return }
                let count = Int(tapBuffer.frameLength)
                let chunk = Array(UnsafeBufferPointer(start: tapData, count: count))
                recordLock.lock()
                recordedSamples.append(contentsOf: chunk)
                recordLock.unlock()
            }

            do {
                try engine.start()
            } catch {
                log("Engine start error: \(error.localizedDescription)")
                return nil
            }

            Thread.sleep(forTimeInterval: Double(durationMs) / 1000.0 + 0.2)

            inputNode.removeTap(onBus: 0)
            engine.stop()

            recordLock.lock()
            let result = recordedSamples
            recordLock.unlock()

            if result.isEmpty { return nil }

            if Int(inputFormat.sampleRate) != sampleRate {
                return resample(result, from: Int(inputFormat.sampleRate), to: sampleRate)
            }
            return result
        }

        private func resample(_ input: [Float], from sourceSR: Int, to targetSR: Int) -> [Float] {
            guard sourceSR != targetSR, !input.isEmpty else { return input }
            let ratio = Double(targetSR) / Double(sourceSR)
            let outputCount = Int(Double(input.count) * ratio)
            var output = [Float](repeating: 0, count: outputCount)
            for i in 0 ..< outputCount {
                let srcIndex = Double(i) / ratio
                let idx = Int(srcIndex)
                let frac = Float(srcIndex - Double(idx))
                if idx + 1 < input.count {
                    output[i] = input[idx] * (1.0 - frac) + input[idx + 1] * frac
                } else if idx < input.count {
                    output[i] = input[idx]
                }
            }
            return output
        }
    }
#endif
