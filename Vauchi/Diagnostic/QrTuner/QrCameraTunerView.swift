// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import AVFoundation
    import CoreImage.CIFilterBuiltins
    import SwiftUI

    // MARK: - Camera Config

    /// A single camera configuration to test during the sweep.
    struct QrTunerCameraConfig: Identifiable {
        let id: Int
        let name: String
        let resolution: AVCaptureSession.Preset
        let cameraPosition: AVCaptureDevice.Position
        let zoomFactor: CGFloat
        let exposureBias: Float

        var positionLabel: String {
            cameraPosition == .front ? "front" : "back"
        }

        var resolutionLabel: String {
            switch resolution {
            case .vga640x480: "480p"
            case .hd1280x720: "720p"
            case .hd1920x1080: "1080p"
            default: "unknown"
            }
        }
    }

    // MARK: - Per-Config Result

    /// Aggregated result for one camera configuration test run.
    struct QrTunerConfigResult: Identifiable {
        let id: Int
        let config: QrTunerCameraConfig
        let framesProcessed: Int
        let qrDetections: Int
        let avgDetectionIntervalMs: Double
        let score: Double

        var decodeRate: Double {
            framesProcessed > 0 ? Double(qrDetections) / Double(framesProcessed) * 100.0 : 0
        }
    }

    // MARK: - Sweep Matrix

    enum QrTunerSweepMatrix {
        static func fullSweep() -> [QrTunerCameraConfig] {
            let positions: [AVCaptureDevice.Position] = [.front, .back]
            let resolutions: [AVCaptureSession.Preset] = [.vga640x480, .hd1280x720, .hd1920x1080]
            let zooms: [CGFloat] = [1.0, 1.5, 2.0]
            let evBiases: [Float] = [-1.0, 0.0, 1.0]

            var configs: [QrTunerCameraConfig] = []
            var idx = 1
            for pos in positions {
                for res in resolutions {
                    for zoom in zooms {
                        for ev in evBiases {
                            let posLabel = pos == .front ? "front" : "back"
                            let resLabel = switch res {
                            case .vga640x480: "480p"
                            case .hd1280x720: "720p"
                            default: "1080p"
                            }
                            configs.append(QrTunerCameraConfig(
                                id: idx,
                                name: "\(posLabel)/\(resLabel)/\(zoom)x/ev\(ev)",
                                resolution: res,
                                cameraPosition: pos,
                                zoomFactor: zoom,
                                exposureBias: ev
                            ))
                            idx += 1
                        }
                    }
                }
            }
            return configs
        }

        /// Front-camera-only sweep matching Android's working config matrix:
        /// 480p, 720p, 1080p at zoom 1.0 with EV -1, 0, +1
        static func frontSweep() -> [QrTunerCameraConfig] {
            let resolutions: [(AVCaptureSession.Preset, String)] = [
                (.vga640x480, "480p"),
                (.hd1280x720, "720p"),
                (.hd1920x1080, "1080p"),
            ]
            let evBiases: [Float] = [-1.0, 0.0, 1.0]

            var configs: [QrTunerCameraConfig] = []
            var idx = 1
            for (res, resLabel) in resolutions {
                for ev in evBiases {
                    configs.append(QrTunerCameraConfig(
                        id: idx,
                        name: "front/\(resLabel)/1.0x/ev\(ev)",
                        resolution: res,
                        cameraPosition: .front,
                        zoomFactor: 1.0,
                        exposureBias: ev
                    ))
                    idx += 1
                }
            }
            return configs
        }

        static func quickSweep() -> [QrTunerCameraConfig] {
            [
                QrTunerCameraConfig(id: 1, name: "front/480p/1x/ev0",
                                    resolution: .vga640x480, cameraPosition: .front,
                                    zoomFactor: 1.0, exposureBias: 0.0),
                QrTunerCameraConfig(id: 2, name: "front/720p/1x/ev0",
                                    resolution: .hd1280x720, cameraPosition: .front,
                                    zoomFactor: 1.0, exposureBias: 0.0),
                QrTunerCameraConfig(id: 3, name: "front/1080p/1x/ev0",
                                    resolution: .hd1920x1080, cameraPosition: .front,
                                    zoomFactor: 1.0, exposureBias: 0.0),
                QrTunerCameraConfig(id: 4, name: "back/720p/1x/ev0",
                                    resolution: .hd1280x720, cameraPosition: .back,
                                    zoomFactor: 1.0, exposureBias: 0.0),
                QrTunerCameraConfig(id: 5, name: "back/1080p/2x/ev0",
                                    resolution: .hd1920x1080, cameraPosition: .back,
                                    zoomFactor: 2.0, exposureBias: 0.0),
            ]
        }
    }

    // MARK: - QR Detection Delegate

    /// Receives metadata output from AVCaptureMetadataOutput and counts QR detections.
    private final class QrTunerMetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let lock = NSLock()
        private(set) var detectionCount: Int = 0
        private(set) var detectionTimestamps: [CFAbsoluteTime] = []
        private(set) var firstDecodedContent: String?
        private var logCallback: ((String) -> Void)?

        func setLogCallback(_ callback: @escaping (String) -> Void) {
            lock.lock()
            logCallback = callback
            lock.unlock()
        }

        func reset() {
            lock.lock()
            detectionCount = 0
            detectionTimestamps = []
            firstDecodedContent = nil
            lock.unlock()
        }

        func snapshot() -> (count: Int, timestamps: [CFAbsoluteTime], firstContent: String?) {
            lock.lock()
            defer { lock.unlock() }
            return (detectionCount, detectionTimestamps, firstDecodedContent)
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            let qrObjects = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
                .filter { $0.type == .qr }
            guard !qrObjects.isEmpty else { return }

            lock.lock()
            detectionCount += qrObjects.count
            detectionTimestamps.append(CFAbsoluteTimeGetCurrent())

            // Log first decoded QR content
            if firstDecodedContent == nil, let content = qrObjects.first?.stringValue {
                firstDecodedContent = content
                let cb = logCallback
                lock.unlock()
                // Log outside lock to avoid deadlock
                let preview = content.count > 80 ? String(content.prefix(80)) + "..." : content
                cb?("DECODED QR (\(content.count) chars): \(preview)")
                return
            }
            lock.unlock()
        }
    }

    // MARK: - Frame Counter Delegate

    /// Counts total video frames processed during each config run.
    private final class QrTunerFrameCounter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let lock = NSLock()
        private(set) var frameCount: Int = 0

        func reset() {
            lock.lock()
            frameCount = 0
            lock.unlock()
        }

        func snapshot() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return frameCount
        }

        func captureOutput(
            _: AVCaptureOutput,
            didOutput _: CMSampleBuffer,
            from _: AVCaptureConnection
        ) {
            lock.lock()
            frameCount += 1
            lock.unlock()
        }
    }

    // MARK: - QrCameraTunerView

    /// Automatable QR camera tuner that sweeps camera configurations and measures
    /// QR detection rate on real devices.
    ///
    /// Launch modes:
    /// - `sweep`: Full config sweep (front+back, 480p+720p+1080p, 3 zooms, 3 EV biases)
    /// - `front`: Front-camera-only sweep (480p+720p+1080p at zoom 1.0, EV -1/0/+1)
    /// - `quick`: 5-config quick test
    /// - `nil`: Interactive mode with buttons
    struct QrCameraTunerView: View {
        /// Auto-test mode: "sweep", "front", "quick", or nil for interactive.
        /// Append "-dual" for dual mode (e.g. "front-dual").
        var autoTest: String?

        @State private var logLines: [String] = []
        @State private var running = false
        @State private var progress: Double = 0
        @State private var results: [QrTunerConfigResult] = []
        @State private var cameraAuthorized = false
        @State private var errorMessage: String?
        @State private var dualMode = false
        @State private var qrOverlayImage: UIImage?

        /// Measurement window per config (seconds). Must be >= 3s to match Android's ~30 frames.
        private static let testDurationSeconds: Double = 4.0

        /// Camera stabilization wait before measurement (seconds).
        private static let stabilizationSeconds: Double = 1.5

        /// Dedicated serial queue for all AVCaptureSession operations.
        private static let sessionQueue = DispatchQueue(label: "com.vauchi.qrtuner.session")

        private static let logFileURL: URL = {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent("qr-tuner.log")
        }()

        var body: some View {
            VStack(spacing: 16) {
                Text("QR Camera Tuner")
                    .font(.title2)
                    .fontWeight(.bold)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if autoTest == nil {
                    HStack(spacing: 12) {
                        Button("Quick Sweep") {
                            startSweep(mode: "quick")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || !cameraAuthorized)

                        Button("Front Sweep") {
                            startSweep(mode: "front")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || !cameraAuthorized)

                        Button("Full Sweep") {
                            startSweep(mode: "sweep")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running || !cameraAuthorized)
                    }

                    Toggle("Dual Mode (show QR while scanning)", isOn: $dualMode)
                        .font(.caption)
                        .padding(.horizontal)
                        .onChange(of: dualMode) { isDual in
                            if isDual {
                                qrOverlayImage = generateQrImage(
                                    "wb://BIDIRECTIONAL_TEST_iPhoneSE_\(Int(Date().timeIntervalSince1970))"
                                )
                            } else {
                                qrOverlayImage = nil
                            }
                        }
                }

                if running {
                    ProgressView(value: progress)
                        .padding(.horizontal)
                    Text("Sweeping... \(Int(progress * 100))%")
                        .font(.caption)
                }

                if !results.isEmpty {
                    resultsSection()
                }

                // Dual mode: show QR overlay below results (simulates bidirectional exchange)
                if dualMode, let qrImage = qrOverlayImage {
                    VStack(spacing: 4) {
                        Text("DUAL MODE: QR displayed while scanning")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                logSection()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                checkCameraAuthorization()
                // Clear log file at start
                try? "".write(to: Self.logFileURL, atomically: true, encoding: .utf8)
                if let mode = autoTest {
                    // Parse dual mode suffix
                    if mode.hasSuffix("-dual") {
                        dualMode = true
                        qrOverlayImage = generateQrImage(
                            "wb://BIDIRECTIONAL_TEST_iPhoneSE_\(Int(Date().timeIntervalSince1970))"
                        )
                        log("DUAL MODE: Showing QR overlay while scanning")
                        startSweep(mode: String(mode.dropLast(5))) // strip "-dual"
                    } else {
                        startSweep(mode: mode)
                    }
                }
            }
        }

        // MARK: - Results UI

        private func resultsSection() -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Results (top 10)")
                    .font(.headline)

                ForEach(Array(results.sorted(by: { $0.score > $1.score }).prefix(10).enumerated()),
                        id: \.offset) { index, result in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(result.config.name)
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(String(format: "%.1f%% / %.3f", result.decodeRate, result.score))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(result.score > 0.5 ? .green : .orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }

        // MARK: - Log UI

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

        // MARK: - Camera Authorization

        private func checkCameraAuthorization() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cameraAuthorized = true
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        cameraAuthorized = granted
                        if !granted {
                            errorMessage = "Camera access is required for QR tuner."
                        }
                    }
                }
            default:
                cameraAuthorized = false
                errorMessage = "Camera access denied. Enable in Settings."
            }
        }

        // MARK: - Sweep Execution

        private func startSweep(mode: String) {
            running = true
            progress = 0
            results = []
            errorMessage = nil

            log("Starting \(mode) sweep...")

            Task {
                let configs: [QrTunerCameraConfig] = switch mode {
                case "sweep":
                    QrTunerSweepMatrix.fullSweep()
                case "front":
                    QrTunerSweepMatrix.frontSweep()
                case "quick":
                    QrTunerSweepMatrix.quickSweep()
                default:
                    QrTunerSweepMatrix.quickSweep()
                }

                log("Testing \(configs.count) configurations, \(Self.testDurationSeconds)s measurement + \(Self.stabilizationSeconds)s stabilization each")

                var allResults: [QrTunerConfigResult] = []

                for (index, config) in configs.enumerated() {
                    log("--- Config \(config.id)/\(configs.count): \(config.name) ---")
                    let result = await testConfig(config)
                    allResults.append(result)

                    let logMsg = String(
                        format: "Config %d: camera=%@ res=%@ zoom=%.1fx ev=%.0f -> frames=%d detections=%d decode=%.1f%% latency=%.0fms",
                        config.id, config.positionLabel, config.resolutionLabel,
                        config.zoomFactor, config.exposureBias,
                        result.framesProcessed, result.qrDetections,
                        result.decodeRate, result.avgDetectionIntervalMs
                    )
                    log(logMsg)

                    await MainActor.run {
                        progress = Double(index + 1) / Double(configs.count)
                        results = allResults
                    }
                }

                // Find best
                let sorted = allResults.sorted { $0.score > $1.score }
                if let best = sorted.first {
                    let bestMsg = String(
                        format: "BEST: config=%d score=%.3f camera=%@ res=%@ zoom=%.1fx ev=%.0f decode=%.1f%%",
                        best.config.id, best.score, best.config.positionLabel,
                        best.config.resolutionLabel, best.config.zoomFactor,
                        best.config.exposureBias, best.decodeRate
                    )
                    log(bestMsg)
                }

                log("Sweep complete. Tested \(allResults.count) configs.")
                log("Log file: Documents/qr-tuner.log")

                await MainActor.run {
                    running = false
                    results = allResults
                }
            }
        }

        // MARK: - Single Config Test

        // swiftlint:disable function_body_length
        /// Tests a single camera configuration, counting frames and QR detections.
        private func testConfig(_ config: QrTunerCameraConfig) async -> QrTunerConfigResult {
            // Get camera device
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: config.cameraPosition
            ) else {
                log("WARN: No \(config.positionLabel) camera available, skipping config \(config.id)")
                return QrTunerConfigResult(
                    id: config.id, config: config,
                    framesProcessed: 0, qrDetections: 0,
                    avgDetectionIntervalMs: 0, score: 0
                )
            }

            let metadataDelegate = QrTunerMetadataDelegate()
            metadataDelegate.setLogCallback { [self] message in
                log(message)
            }
            let frameCounter = QrTunerFrameCounter()

            // Set up and run capture session on the dedicated session queue
            return await withCheckedContinuation { continuation in
                Self.sessionQueue.async {
                    let session = AVCaptureSession()
                    session.beginConfiguration()
                    session.sessionPreset = config.resolution

                    guard let input = try? AVCaptureDeviceInput(device: device),
                          session.canAddInput(input)
                    else {
                        NSLog("[Vauchi] [QR Tuner] WARN: Cannot create input for config %d", config.id)
                        session.commitConfiguration()
                        continuation.resume(returning: QrTunerConfigResult(
                            id: config.id, config: config,
                            framesProcessed: 0, qrDetections: 0,
                            avgDetectionIntervalMs: 0, score: 0
                        ))
                        return
                    }
                    session.addInput(input)

                    // Add metadata output for QR detection
                    let metadataOutput = AVCaptureMetadataOutput()
                    let metadataQueue = DispatchQueue(label: "com.vauchi.qrtuner.metadata.\(config.id)")

                    guard session.canAddOutput(metadataOutput) else {
                        NSLog("[Vauchi] [QR Tuner] WARN: Cannot add metadata output for config %d", config.id)
                        session.commitConfiguration()
                        continuation.resume(returning: QrTunerConfigResult(
                            id: config.id, config: config,
                            framesProcessed: 0, qrDetections: 0,
                            avgDetectionIntervalMs: 0, score: 0
                        ))
                        return
                    }
                    session.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(metadataDelegate, queue: metadataQueue)

                    // Add video data output for frame counting
                    let videoOutput = AVCaptureVideoDataOutput()
                    let videoQueue = DispatchQueue(label: "com.vauchi.qrtuner.video.\(config.id)")

                    if session.canAddOutput(videoOutput) {
                        session.addOutput(videoOutput)
                        videoOutput.setSampleBufferDelegate(frameCounter, queue: videoQueue)
                        videoOutput.alwaysDiscardsLateVideoFrames = true
                    }

                    // CRITICAL: Commit configuration BEFORE setting metadataObjectTypes.
                    // availableMetadataObjectTypes is empty until the session config is committed.
                    session.commitConfiguration()

                    // Now set QR type after commit
                    let availableTypes = metadataOutput.availableMetadataObjectTypes
                    if availableTypes.contains(.qr) {
                        metadataOutput.metadataObjectTypes = [.qr]
                        NSLog("[Vauchi] [QR Tuner] Config %d: QR metadata type set successfully (available: %d types)",
                              config.id, availableTypes.count)
                    } else {
                        NSLog("[Vauchi] [QR Tuner] WARN: Config %d: .qr NOT in availableMetadataObjectTypes! Available: %@",
                              config.id, availableTypes.map(\.rawValue).description)
                    }

                    // Apply zoom and exposure bias
                    do {
                        try device.lockForConfiguration()

                        // Zoom factor (clamped to device max)
                        let maxZoom = min(config.zoomFactor, device.activeFormat.videoMaxZoomFactor)
                        if maxZoom >= 1.0 {
                            device.videoZoomFactor = maxZoom
                        }

                        // Exposure target bias (clamped to device range)
                        let clampedEv = min(max(config.exposureBias, device.minExposureTargetBias),
                                            device.maxExposureTargetBias)
                        device.setExposureTargetBias(clampedEv, completionHandler: nil)

                        // Enable auto-focus for continuous scanning if supported
                        if device.isFocusModeSupported(.continuousAutoFocus) {
                            device.focusMode = .continuousAutoFocus
                        }

                        device.unlockForConfiguration()
                    } catch {
                        NSLog("[Vauchi] [QR Tuner] WARN: Failed to configure device for config %d: %@",
                              config.id, error.localizedDescription)
                    }

                    // Start the session
                    session.startRunning()
                    NSLog("[Vauchi] [QR Tuner] Config %d: session running=%d", config.id, session.isRunning ? 1 : 0)

                    // Wait for camera stabilization
                    let stabMs = Int(Self.stabilizationSeconds * 1000)
                    Thread.sleep(forTimeInterval: Self.stabilizationSeconds)

                    // Reset counters after stabilization
                    metadataDelegate.reset()
                    frameCounter.reset()

                    NSLog("[Vauchi] [QR Tuner] Config %d: stabilized (%dms), starting %0.1fs measurement",
                          config.id, stabMs, Self.testDurationSeconds)

                    // Measure for testDurationSeconds
                    Thread.sleep(forTimeInterval: Self.testDurationSeconds)

                    // Collect results
                    let detectionSnapshot = metadataDelegate.snapshot()
                    let frameCount = frameCounter.snapshot()

                    session.stopRunning()

                    NSLog("[Vauchi] [QR Tuner] Config %d: frames=%d detections=%d firstContent=%@",
                          config.id, frameCount, detectionSnapshot.count,
                          detectionSnapshot.firstContent != nil ? "yes" : "no")

                    // Calculate average detection interval
                    let avgIntervalMs: Double
                    if detectionSnapshot.timestamps.count > 1 {
                        var intervals: [Double] = []
                        for i in 1 ..< detectionSnapshot.timestamps.count {
                            intervals.append(
                                (detectionSnapshot.timestamps[i] - detectionSnapshot.timestamps[i - 1]) * 1000.0
                            )
                        }
                        avgIntervalMs = intervals.reduce(0, +) / Double(intervals.count)
                    } else {
                        avgIntervalMs = 0
                    }

                    // Score: decodeRate * 0.7 + (1 - normalizedLatency) * 0.3
                    let decodeRate = frameCount > 0 ? Double(detectionSnapshot.count) / Double(frameCount) : 0
                    let normalizedLatency = min(avgIntervalMs / 200.0, 1.0)
                    let score = decodeRate * 0.7 + (1.0 - normalizedLatency) * 0.3

                    continuation.resume(returning: QrTunerConfigResult(
                        id: config.id,
                        config: config,
                        framesProcessed: frameCount,
                        qrDetections: detectionSnapshot.count,
                        avgDetectionIntervalMs: avgIntervalMs,
                        score: score
                    ))
                }
            }
        }

        // swiftlint:enable function_body_length

        // MARK: - QR Generation (Dual Mode)

        /// Generate a QR code image using Core Image for dual mode overlay.
        private func generateQrImage(_ data: String) -> UIImage? {
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
            filter.setValue(data.data(using: .utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let ciImage = filter.outputImage else { return nil }
            // Scale up from tiny CIFilter output to usable size
            let scale = 10.0
            let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = CIContext()
            guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
            return UIImage(cgImage: cgImage)
        }

        // MARK: - Logging

        private func log(_ message: String) {
            let tagged = "[QR Tuner] \(message)"
            NSLog("[Vauchi] %@", tagged)

            // Append to file
            let line = "[\(Self.timeStamp())] \(tagged)\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: Self.logFileURL)
                }
            }

            DispatchQueue.main.async {
                logLines.append("[\(Self.timeStamp())] \(message)")
            }
        }

        private static func timeStamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: Date())
        }
    }
#endif
