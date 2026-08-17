// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Ultrasonic audio proximity verification for Vauchi iOS
// Audio proximity methods (PlatformAudioHandler removed in core 0.19.21, ADR-031)

import Accelerate
import AVFoundation
import VauchiPlatform

/// Service for ultrasonic audio proximity verification.
/// Uses AVAudioEngine to emit and receive signals at 18-20 kHz.
class AudioProximityService {
    /// Why audio proximity could not run.
    ///
    /// Named causes rather than AVFoundation's own errors, so a caller can
    /// report why nothing was emitted instead of the process dying.
    private enum AudioProximityError: LocalizedError {
        case microphoneNotGranted
        case engineNotRunning

        var errorDescription: String? {
            switch self {
            case .microphoneNotGranted:
                "Microphone permission not granted"
            case .engineNotRunning:
                "Audio engine did not start"
            }
        }
    }

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
        // Best effort at construction; every use site re-establishes the
        // session and reports its own failure, so a denial here is not fatal.
        try? ensureSessionActive()
    }

    deinit {
        stop()
    }

    /// Whether the user has actually granted the microphone.
    ///
    /// `.playAndRecord` cannot be activated without it, so this is the
    /// difference between "the hardware exists" and "we may use it" — and
    /// the two were previously conflated (see `checkCapability`).
    private var microphoneGranted: Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Bring the audio session up, or throw saying why.
    ///
    /// This used to swallow its own failure and print in DEBUG only, while
    /// both call sites wrote `try setupAudioSession()` against a
    /// non-throwing function — so a session that never activated looked
    /// exactly like one that did, and the code proceeded to drive
    /// AVAudioEngine on it. That is what crashed the app
    /// (`2026-08-17-ios-audio-proximity-crashes-the-app`).
    private func ensureSessionActive() throws {
        guard microphoneGranted else {
            throw AudioProximityError.microphoneNotGranted
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(targetSampleRate)
        try session.setActive(true)
    }

    // MARK: - Audio Methods

    /// Check device capability for ultrasonic audio.
    func checkCapability() -> String {
        let session = AVAudioSession.sharedInstance()

        // Deliberately answers only the hardware question. A missing grant is
        // NOT reported as absent hardware: Core maps absence to
        // `ModeAvailability::Unavailable`, which has no grant path, so the
        // audio-proximity modes would disappear from the picker instead of
        // offering to re-prompt — and on a first run, where the permission is
        // merely undetermined, they would disappear before the user was ever
        // asked. Denial belongs in `TransportReadiness`, which yields
        // `PermissionRequired` and a grant affordance; this shell does not
        // report that yet (see the record's follow-up).
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
            try ensureSessionActive()

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

            // `play()` raises an Objective-C exception if the engine is not
            // running. Swift cannot catch that — the surrounding `do/catch`
            // looks protective but only handles Swift errors, so the raise
            // goes straight to std::terminate and aborts the process. The
            // state is therefore checked, because it cannot be caught.
            guard audioEngine.isRunning else {
                audioEngine.detach(player)
                throw AudioProximityError.engineNotRunning
            }

            isPlaying = true
            playerNode = player

            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                }
            }
            player.play()

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
            try ensureSessionActive()

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
