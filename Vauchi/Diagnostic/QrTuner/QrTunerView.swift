// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreImage
import os
import SwiftUI
import VauchiMobile

/// Main entry point for the QR camera tuner diagnostic.
///
/// Probes device capabilities, generates a sweep matrix, iterates through
/// camera configurations while decoding QR codes from frames, and ranks
/// the results.
struct QrTunerView: View {
    @State private var logLines: [String] = []
    @State private var running = false
    @State private var profile: MobileDeviceCapabilityProfile?
    @State private var rankedResults: [MobileScoredConfig] = []
    @State private var sweepProgress: Double = 0
    @State private var cameraAuthorized = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.vauchi.qrtuner", category: "view")
    private let sessionId = UUID().uuidString.prefix(8).lowercased()

    var body: some View {
        VStack(spacing: 16) {
            Text("QR Camera Tuner")
                .font(.title2)
                .fontWeight(.bold)

            if let profile {
                deviceInfoSection(profile)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Probe Device") {
                    probeDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)

                Button("Start Sweep") {
                    startSweep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(running || profile == nil || !cameraAuthorized)
            }

            if running {
                ProgressView(value: sweepProgress)
                    .padding(.horizontal)
                Text("Sweeping... \(Int(sweepProgress * 100))%")
                    .font(.caption)
            }

            if !rankedResults.isEmpty {
                resultsSection()
            }

            logSection()
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkCameraAuthorization()
        }
    }

    // MARK: - UI Sections

    private func deviceInfoSection(_ profile: MobileDeviceCapabilityProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Device: \(profile.deviceModel)")
                .font(.caption)
            if let isoMin = profile.isoRangeMin, let isoMax = profile.isoRangeMax {
                Text("ISO: \(isoMin)–\(isoMax)")
                    .font(.caption)
            }
            if let evMin = profile.exposureEvRangeMin, let evMax = profile.exposureEvRangeMax {
                Text("EV: \(evMin)–\(evMax)")
                    .font(.caption)
            }
            Text("AF: \(profile.afModes.joined(separator: ", "))")
                .font(.caption)
            Text("AWB: \(profile.awbModes.joined(separator: ", "))")
                .font(.caption)
            Text("Resolution: \(profile.maxResolutionWidth)x\(profile.maxResolutionHeight)")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func resultsSection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ranked Results")
                .font(.headline)

            ForEach(Array(rankedResults.prefix(10).enumerated()), id: \.offset) { index, scored in
                HStack {
                    Text("#\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Text("Config \(scored.configId)")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text(String(format: "%.3f", scored.score))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func logSection() -> some View {
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

    // MARK: - Actions

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    if !granted {
                        errorMessage = "Camera access is required for the QR tuner."
                    }
                }
            }
        default:
            cameraAuthorized = false
            errorMessage = "Camera access denied. Enable in Settings."
        }
    }

    private func probeDevice() {
        log("Probing device capabilities...")
        let result = DeviceCapabilityProbe.probe()
        profile = result
        log("Device: \(result.deviceModel)")
        log("ISO: \(result.isoRangeMin.map(String.init) ?? "n/a")–\(result.isoRangeMax.map(String.init) ?? "n/a")")
        log("AF modes: \(result.afModes.joined(separator: ", "))")
        log("AWB modes: \(result.awbModes.joined(separator: ", "))")
        log("Max resolution: \(result.maxResolutionWidth)x\(result.maxResolutionHeight)")
        log("FPS ranges: \(result.fpsRanges.map { "\($0.min)-\($0.max)" }.joined(separator: ", "))")
        log("Probe complete.")
    }

    private func startSweep() {
        guard let profile else { return }

        running = true
        sweepProgress = 0
        rankedResults = []
        errorMessage = nil

        Task {
            await performSweep(profile: profile)
            await MainActor.run {
                running = false
            }
        }
    }

    // MARK: - Sweep Logic

    private func performSweep(profile: MobileDeviceCapabilityProfile) async {
        await log("Generating sweep matrix...")
        let matrix = diagnosticGenerateSweepMatrix(profile: profile)
        let configCount = matrix.cameraConfigs.count
        await log("Generated \(configCount) camera configs, \(matrix.qrConfigs.count) QR configs")

        guard let (session, device, delegate) = await setupCaptureSession() else { return }
        defer { session.stopRunning() }

        await log("Camera session started. Session ID: \(sessionId)")

        let qrConfig = matrix.qrConfigs.first ?? MobileQrConfig(
            errorCorrection: .m, payloadSizeBytes: 100, moduleSizePx: 10
        )
        let ciDetector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )

        let tuningResults = await runConfigSweep(
            configs: matrix.cameraConfigs, device: device,
            delegate: delegate, detector: ciDetector, qrConfig: qrConfig
        )

        await log("Ranking \(tuningResults.count) results...")
        let ranked = diagnosticRankConfigs(results: tuningResults)
        await MainActor.run { rankedResults = ranked }

        saveSummary(results: tuningResults, ranked: ranked)
        await log("Sweep complete. Top config: \(ranked.first.map { "id=\($0.configId) score=\(String(format: "%.3f", $0.score))" } ?? "none")")
    }

    private func setupCaptureSession() async -> (AVCaptureSession, AVCaptureDevice, FrameCaptureDelegate)? {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            await log("ERROR: No front camera available")
            return nil
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            await log("ERROR: Cannot create/add device input")
            return nil
        }
        session.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        guard session.canAddOutput(videoOutput) else {
            await log("ERROR: Cannot add video output to session")
            return nil
        }
        session.addOutput(videoOutput)

        let delegate = FrameCaptureDelegate()
        videoOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.vauchi.qrtuner.capture"))
        session.startRunning()

        return (session, device, delegate)
    }

    private func runConfigSweep(
        configs: [MobileCameraConfig], device: AVCaptureDevice,
        delegate: FrameCaptureDelegate, detector: CIDetector?, qrConfig: MobileQrConfig
    ) async -> [MobileTuningResult] {
        var results: [MobileTuningResult] = []
        let total = configs.count

        for (index, config) in configs.enumerated() {
            do {
                try CameraConfigTuner.applyConfig(config, to: device)
            } catch {
                await log("WARN: Failed to apply config \(config.id): \(error.localizedDescription)")
                continue
            }

            let run = await CameraConfigTuner.runConfig(configId: config.id) {
                await captureAndDecode(
                    delegate: delegate, detector: detector,
                    configId: config.id, sessionId: String(sessionId)
                )
            }

            let result = CameraConfigTuner.toTuningResult(
                run: run, qrConfig: qrConfig,
                actualIso: Int32(device.iso),
                actualExposureEv: Int32(device.exposureTargetBias)
            )
            results.append(result)

            await MainActor.run { sweepProgress = Double(index + 1) / Double(total) }

            if index % 10 == 0 || index == total - 1 {
                await log("Config \(config.id): decode=\(String(format: "%.0f%%", result.decodeRate * 100)) latency=\(String(format: "%.1fms", result.avgLatencyMs))")
            }
        }
        return results
    }

    private func captureAndDecode(
        delegate: FrameCaptureDelegate,
        detector: CIDetector?,
        configId _: UInt32,
        sessionId _: String
    ) async -> FrameResult {
        let startNs = DispatchTime.now().uptimeNanoseconds

        // Wait for next frame
        guard let pixelBuffer = await delegate.nextFrame() else {
            return FrameResult(decoded: false, latencyMs: 0, timestampNs: startNs)
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let features = detector?.features(in: ciImage) ?? []
        let decoded = features.contains { $0 is CIQRCodeFeature }

        let endNs = DispatchTime.now().uptimeNanoseconds
        let latencyMs = Float(endNs - startNs) / 1_000_000.0

        return FrameResult(
            decoded: decoded,
            latencyMs: latencyMs,
            timestampNs: startNs
        )
    }

    private func saveSummary(results: [MobileTuningResult], ranked: [MobileScoredConfig]) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("diagnostic")
            .appendingPathComponent("tuner")
            .appendingPathComponent("session_\(sessionId)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let summary: [String: Any] = [
            "session_id": String(sessionId),
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "total_configs": results.count,
            "top_config_id": ranked.first?.configId ?? 0,
            "top_score": ranked.first?.score ?? 0,
        ]

        let path = dir.appendingPathComponent("summary.json")
        if let data = try? JSONSerialization.data(
            withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: path)
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        logger.info("\(message)")
        DispatchQueue.main.async {
            logLines.append(message)
        }
    }

    @MainActor
    private func log(_ message: String) async {
        logger.info("\(message)")
        logLines.append(message)
    }
}

// MARK: - Frame Capture Delegate

/// Captures video frames from `AVCaptureVideoDataOutput` and provides
/// them to the sweep loop via async continuation.
private final class FrameCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var continuation: CheckedContinuation<CVPixelBuffer?, Never>?
    private let lock = NSLock()

    func nextFrame() async -> CVPixelBuffer? {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        // CMSampleBufferGetImageBuffer returns unretained; assigning to a
        // Swift optional lets ARC retain the pixel buffer automatically so
        // it outlives the sample buffer.
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        continuation.resume(returning: pixelBuffer)
    }
}
