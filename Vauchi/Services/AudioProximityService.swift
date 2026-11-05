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

    /// Playback and capture use independent engines and operation owners.
    ///
    /// `emit_proximity_commands` sends `AudioEmitChallenge` and
    /// `AudioListenForResponse` as one batch — the responder is even told to
    /// listen first — so emit and listen are always in flight together. They
    /// used to share one AVAudioEngine, and installing the capture tap
    /// reconfigures a running engine: the IO unit is torn down and rebuilt
    /// while `isRunning` still answers `true`. The emit path then passed its
    /// `isRunning` guard and called `AVAudioPlayerNode.play()` on an engine
    /// that was not running, which raises an Objective-C exception Swift
    /// cannot catch, and the process aborts
    /// (`2026-08-17-ios-audio-proximity-crashes-the-app`).
    ///
    /// Serializing the two paths against one engine does not fix this — the
    /// reconfiguration outlives the critical section, and making them take
    /// turns would leave the responder emitting only after its own 5-second
    /// listen expired. Separate engines keep them concurrent and stop either
    /// one from reconfiguring the other. Each owner serializes replacement
    /// and stop against its engine's start-and-use sequence.
    private let playbackEngine = AVAudioEngine()
    private let captureEngine = AVAudioEngine()
    private let playback = AudioOperationSlot()
    private let capture = AudioOperationSlot()

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
    func emitSignal(samples: [Float], sampleRate: UInt32, request: AudioOperationSlot.Request? = nil) -> String {
        guard !samples.isEmpty else {
            return "No samples to emit"
        }
        let request = request ?? playback.reserve()

        do {
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
            var attached = false
            let duration = Double(samples.count) / Double(sampleRate)
            try playback.run(for: duration + 0.1, request: request, start: {
                try ensureSessionActive()
                playbackEngine.attach(player)
                attached = true
                playbackEngine.connect(player, to: playbackEngine.mainMixerNode, format: format)
                try playbackEngine.start()
                guard playbackEngine.isRunning else {
                    throw AudioProximityError.engineNotRunning
                }
                player.scheduleBuffer(buffer, at: nil, options: [])
                player.play()
            }, stop: { [self] in
                if attached {
                    player.stop()
                    playbackEngine.stop()
                    playbackEngine.detach(player)
                }
            })

            return "" // Success

        } catch {
            return "Emit failed: \(error.localizedDescription)"
        }
    }

    func emitSignal(samples: [Float], sampleRate: UInt32, completion: @escaping (String) -> Void) {
        let request = playback.reserve()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = emitSignal(samples: samples, sampleRate: sampleRate, request: request)
            DispatchQueue.main.async { [self] in
                playback.deliver(request) { completion(result) }
            }
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
        let request = capture.reserve()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let service = self else { return }
            let (samples, recordedRate) = service.recordSamples(timeoutMs: timeoutMs, request: request)
            DispatchQueue.main.async {
                service.capture.deliver(request) { completion(samples, recordedRate) }
            }
        }
    }

    /// Synchronous variant for diagnostic/loopback tools that already run on a
    /// background thread. Production code (`ExchangeCommandHandler`) uses the
    /// callback-based `receiveSignal` instead.
    func receiveSignalSync(timeoutMs: UInt64, sampleRate _: UInt32) -> [Float] {
        recordSamples(timeoutMs: timeoutMs).samples
    }

    private func recordSamples(
        timeoutMs: UInt64, request: AudioOperationSlot.Request? = nil
    ) -> (samples: [Float], recordedRate: UInt32) {
        let request = request ?? capture.reserve()
        let sampleLock = NSLock()
        var recordedSamples: [Float] = []
        var acceptingSamples = true
        var recordedRate: UInt32 = 0
        var inputNode: AVAudioInputNode?
        var tapInstalled = false
        do {
            try capture.run(for: Double(timeoutMs) / 1000, request: request, start: {
                try ensureSessionActive()
                let node = captureEngine.inputNode
                inputNode = node
                let inputFormat = node.outputFormat(forBus: 0)
                recordedRate = UInt32(inputFormat.sampleRate)
                node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self else { return }
                    let samples = extractSamples(from: buffer)
                    sampleLock.lock()
                    if acceptingSamples {
                        recordedSamples.append(contentsOf: samples)
                    }
                    sampleLock.unlock()
                }
                tapInstalled = true
                try captureEngine.start()
                guard captureEngine.isRunning else {
                    throw AudioProximityError.engineNotRunning
                }
            }, stop: { [self] in
                sampleLock.lock()
                acceptingSamples = false
                sampleLock.unlock()
                if tapInstalled {
                    inputNode?.removeTap(onBus: 0)
                }
                captureEngine.stop()
            })

            sampleLock.lock()
            let result = recordedSamples
            sampleLock.unlock()

            return (samples: result, recordedRate: recordedRate)

        } catch {
            #if DEBUG
                print("AudioProximityService: Recording failed: \(error)")
            #endif
            return (samples: [], recordedRate: 0)
        }
    }

    /// Check if audio is currently active.
    func isActive() -> Bool {
        capture.isActive || playback.isActive
    }

    /// Stop any ongoing audio operation.
    func stop() {
        playback.stop()
        capture.stop()
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
