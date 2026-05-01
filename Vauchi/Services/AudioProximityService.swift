// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AudioProximityService.swift
// Ultrasonic audio proximity verification for Vauchi iOS
// Audio proximity methods (PlatformAudioHandler removed in core 0.19.21, ADR-031)

import Accelerate
import AVFoundation
import VauchiPlatform

/// Service for ultrasonic audio proximity verification.
/// Uses AVAudioEngine to emit and receive signals at 18-20 kHz.
class AudioProximityService {
    // MARK: - Audio Engine

    private let audioEngine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var isRecording = false
    private var isPlaying = false
    private var recordedSamples: [Float] = []
    private let sampleLock = NSLock()

    // MARK: - Configuration

    private let targetSampleRate: Double = 44100
    private let ultrasonicMinFreq: Float = 18000
    private let ultrasonicMaxFreq: Float = 20000

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    deinit {
        stop()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(targetSampleRate)
            try session.setActive(true)
        } catch {
            #if DEBUG
                print("AudioProximityService: Failed to setup audio session: \(error)")
            #endif
        }
    }

    // MARK: - Audio Methods

    /// Check device capability for ultrasonic audio.
    func checkCapability() -> String {
        let session = AVAudioSession.sharedInstance()

        let hasInput = session.isInputAvailable
        let hasOutput = session.currentRoute.outputs.count > 0

        // Check if sample rate supports ultrasonic frequencies
        let sampleRate = session.sampleRate
        let nyquist = sampleRate / 2
        let supportsUltrasonic = nyquist >= Double(ultrasonicMaxFreq)

        if !supportsUltrasonic {
            return "none"
        }

        if hasInput, hasOutput {
            return "full"
        } else if hasOutput {
            return "emit_only"
        } else if hasInput {
            return "receive_only"
        } else {
            return "none"
        }
    }

    /// Emit ultrasonic signal with given samples.
    func emitSignal(samples: [Float], sampleRate: UInt32) -> String {
        guard !samples.isEmpty else {
            return "No samples to emit"
        }

        do {
            try setupAudioSession()

            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
                return "Failed to create audio format"
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                return "Failed to create audio buffer"
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)

            guard let floatChannelData = buffer.floatChannelData else {
                return "Failed to access float channel data"
            }
            let channelData = floatChannelData[0]
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }

            let player = AVAudioPlayerNode()
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)

            try audioEngine.start()

            isPlaying = true
            playerNode = player

            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                }
            }
            player.play()

            // Wait for playback to complete
            let duration = Double(samples.count) / Double(sampleRate)
            Thread.sleep(forTimeInterval: duration + 0.1)

            player.stop()
            audioEngine.stop()
            audioEngine.detach(player)
            playerNode = nil
            isPlaying = false

            return "" // Success

        } catch {
            isPlaying = false
            return "Emit failed: \(error.localizedDescription)"
        }
    }

    /// Record audio for `timeoutMs` and report samples + actual rate via callback.
    ///
    /// `sampleRate` is core's suggested rate; the device may record at a different
    /// rate (typically 48 kHz on modern iPhones). The actual rate is reported
    /// alongside the samples so core can resample as needed (Phase 1 resampler).
    /// Recording runs on a background queue; callback fires on the main queue.
    func receiveSignal(
        timeoutMs: UInt64,
        sampleRate _: UInt32,
        completion: @escaping ([Float], UInt32) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion([], 0) }
                return
            }
            let (samples, recordedRate) = recordSamples(timeoutMs: timeoutMs)
            DispatchQueue.main.async {
                completion(samples, recordedRate)
            }
        }
    }

    /// Synchronous variant for diagnostic/loopback tools that already run on a
    /// background thread. Production code (`ExchangeCommandHandler`) uses the
    /// callback-based `receiveSignal` instead.
    func receiveSignalSync(timeoutMs: UInt64, sampleRate _: UInt32) -> [Float] {
        recordSamples(timeoutMs: timeoutMs).samples
    }

    private func recordSamples(timeoutMs: UInt64) -> (samples: [Float], recordedRate: UInt32) {
        do {
            try setupAudioSession()

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let recordedRate = UInt32(inputFormat.sampleRate)

            sampleLock.lock()
            recordedSamples = []
            sampleLock.unlock()

            isRecording = true

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self, isRecording else { return }

                let samples = extractSamples(from: buffer)

                sampleLock.lock()
                recordedSamples.append(contentsOf: samples)
                sampleLock.unlock()
            }

            try audioEngine.start()

            Thread.sleep(forTimeInterval: Double(timeoutMs) / 1000.0)

            isRecording = false
            inputNode.removeTap(onBus: 0)
            audioEngine.stop()

            sampleLock.lock()
            let result = recordedSamples
            recordedSamples = []
            sampleLock.unlock()

            return (samples: result, recordedRate: recordedRate)

        } catch {
            #if DEBUG
                print("AudioProximityService: Recording failed: \(error)")
            #endif
            isRecording = false
            return (samples: [], recordedRate: 0)
        }
    }

    /// Check if audio is currently active.
    func isActive() -> Bool {
        isRecording || isPlaying
    }

    /// Stop any ongoing audio operation.
    func stop() {
        isRecording = false
        isPlaying = false

        playerNode?.stop()
        playerNode = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    // MARK: - Helper Methods

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let frameCount = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frameCount)

        // Copy samples from first channel
        for i in 0 ..< frameCount {
            samples[i] = channelData[0][i]
        }

        return samples
    }
}

// MARK: - Shared Instance

extension AudioProximityService {
    static let shared = AudioProximityService()
}
