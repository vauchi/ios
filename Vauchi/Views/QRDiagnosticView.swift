// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// QRDiagnosticView.swift
// Standalone QR scanning diagnostic — tests QR generation, front-camera
// detection, and reports live stats to find the optimal configuration
// for the multi-stage exchange protocol.

#if DEBUG
    import AVFoundation
    import CoreImage.CIFilterBuiltins
    import SwiftUI

    // MARK: - Test QR Complexity Levels

    enum QrTestLevel: String, CaseIterable {
        case tiny = "Tiny 10ch"
        case short = "Short 50ch"
        case initStage = "INIT ~190ch"
        case dataStage = "DATA ~700ch"

        var sampleContent: String {
            switch self {
            case .tiny:
                return "HELLO12345"
            case .short:
                return "INIT:" + String(repeating: "A", count: 45)
            case .initStage:
                let sid = "0123456789ABCDEFGHIJKLMN" // 24 chars
                let pk = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLM" // 48 chars
                let eph = "NOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" // 48 chars
                let ch = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ012345678901AB" // 48 chars
                return "INIT\(sid)\(pk)\(eph)\(ch)VAUCHI USER"
            case .dataStage:
                let sid = "0123456789ABCDEFGHIJKLMN"
                let payload = String((0 ..< 450).map { i in
                    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                    return chars[chars.index(chars.startIndex, offsetBy: i % 36)]
                })
                return "DATA\(sid)001/001FF A1B2 \(payload)"
            }
        }
    }

    // MARK: - Detection Stats

    class DiagnosticStats: ObservableObject {
        @Published var frameCount: Int = 0
        @Published var detectionCount: Int = 0
        @Published var lastDetected: String = ""
        @Published var lastDetectedTime: Date?
        @Published var resolution: String = "—"

        var detectionRate: String {
            guard frameCount > 0 else { return "—" }
            return String(format: "%.1f%%", Double(detectionCount) / Double(frameCount) * 100)
        }

        func recordDetection(_ content: String) {
            DispatchQueue.main.async {
                self.detectionCount += 1
                self.lastDetected = content
                self.lastDetectedTime = Date()
            }
        }

        func reset() {
            frameCount = 0
            detectionCount = 0
            lastDetected = ""
            lastDetectedTime = nil
        }
    }

    // MARK: - Diagnostic QR Scanner (front camera, with stats)

    class DiagnosticQrScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
        private var captureSession: AVCaptureSession?
        private var stats: DiagnosticStats?
        private var onDetected: ((String) -> Void)?
        private var lastCode: String?
        private var lastTime: Date?

        func start(stats: DiagnosticStats, onDetected: @escaping (String) -> Void) {
            self.stats = stats
            self.onDetected = onDetected
            setupCamera()
        }

        func stop() {
            captureSession?.stopRunning()
            captureSession = nil
        }

        private func setupCamera() {
            captureSession?.stopRunning()

            let session = AVCaptureSession()
            session.sessionPreset = .hd1280x720

            // Front camera only
            var device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            if device == nil {
                // Fallback to rear if no front camera (simulator)
                device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }

            guard let cam = device, let input = try? AVCaptureDeviceInput(device: cam) else {
                DispatchQueue.main.async {
                    self.stats?.resolution = "No camera"
                }
                return
            }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            // Report resolution
            let dims = CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription)
            DispatchQueue.main.async {
                self.stats?.resolution = "\(dims.width)x\(dims.height) front"
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                if output.availableMetadataObjectTypes.contains(.qr) {
                    output.metadataObjectTypes = [.qr]
                }
            }

            captureSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            // Count frames (approximation — metadata callback fires per frame with QR)
            DispatchQueue.main.async {
                self.stats?.frameCount += 1
            }

            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = obj.stringValue
            else { return }

            // Debounce identical codes within 1s
            if let last = lastCode, let time = lastTime,
               last == code, Date().timeIntervalSince(time) < 1.0 {
                return
            }

            lastCode = code
            lastTime = Date()
            stats?.recordDetection(code)
            onDetected?(code)
        }

        deinit {
            captureSession?.stopRunning()
        }
    }

    // MARK: - QR Diagnostic View

    struct QRDiagnosticView: View {
        /// Set to "all" or "generation" to auto-run tests on appear
        var autoTest: String?

        @State private var qrTestLevel: QrTestLevel = .initStage
        @State private var ecLevel: String = "M"
        @State private var cameraGranted = false
        @State private var permissionsChecked = false
        @State private var autoTestRunning = false
        @State private var autoTestLines: [String] = []
        @StateObject private var stats = DiagnosticStats()
        @StateObject private var scanner = DiagnosticQrScanner()

        /// File-based logging for automation retrieval
        private static let logFileURL: URL = {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent("qr-diagnostic.log")
        }()

        var body: some View {
            ScrollView {
                VStack(spacing: 12) {
                    if autoTestRunning || !autoTestLines.isEmpty {
                        // Auto-test log output
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(autoTestLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(line.contains("FAIL") ? .red : line.contains("PASS") ? .green : .primary)
                            }
                        }
                        .padding()
                    } else {
                        // QR display
                        qrDisplay

                        // Controls
                        complexityPicker
                        ecPicker

                        // Stats
                        statsCard

                        // Camera status
                        cameraStatus
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("QR Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let test = autoTest {
                    runAutoTest(test)
                } else {
                    requestPermissions()
                }
            }
            .onDisappear {
                scanner.stop()
            }
            .onChange(of: cameraGranted) { granted in
                if granted, autoTest == nil {
                    startScanner()
                }
            }
        }

        // MARK: - Auto Test

        private func runAutoTest(_ test: String) {
            autoTestRunning = true
            Self.clearLogFile()
            log("=== QR Diagnostic Auto-Test ===")
            log("Test: \(test)")

            DispatchQueue.global(qos: .userInitiated).async {
                switch test {
                case "generation", "all":
                    testQrGeneration()
                    if test == "all" {
                        testCameraInit()
                    }
                case "camera":
                    testCameraInit()
                default:
                    log("Unknown test: \(test)")
                }

                log("=== QR Diagnostic Complete ===")
                DispatchQueue.main.async { autoTestRunning = false }
            }
        }

        private func testQrGeneration() {
            log("--- Test: QR Generation ---")
            let ecLevels = ["L", "M", "Q", "H"]
            var passed = 0
            var failed = 0

            for level in QrTestLevel.allCases {
                let content = level.sampleContent
                for ec in ecLevels {
                    let image = generateQRCode(from: content, correctionLevel: ec)
                    if image != nil {
                        passed += 1
                    } else {
                        failed += 1
                        log("FAIL: Generation failed for \(level.rawValue) EC-\(ec) (\(content.count) chars)")
                    }
                }
                let allEcOk = ecLevels.allSatisfy { generateQRCode(from: content, correctionLevel: $0) != nil }
                log("\(allEcOk ? "PASS" : "FAIL"): \(level.rawValue) (\(content.count) chars) — all EC levels")
            }

            log("Generation summary: \(passed) passed, \(failed) failed out of \(passed + failed)")
        }

        private func testCameraInit() {
            log("--- Test: Camera Init ---")
            let semaphore = DispatchSemaphore(value: 0)
            var result = "UNKNOWN"

            DispatchQueue.main.async {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:
                    result = "PASS"
                    log("PASS: Camera permission granted")
                case .notDetermined:
                    result = "SKIP"
                    log("SKIP: Camera permission not yet requested (requires UI)")
                case .denied, .restricted:
                    result = "FAIL"
                    log("FAIL: Camera permission denied/restricted")
                @unknown default:
                    result = "UNKNOWN"
                    log("UNKNOWN: Camera permission status unknown")
                }

                // Check front camera availability
                if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
                    log("PASS: Front camera available")
                } else if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
                    log("PASS: Rear camera available (no front camera)")
                } else {
                    log("FAIL: No camera available")
                }
                semaphore.signal()
            }
            semaphore.wait()
        }

        private func log(_ msg: String) {
            let ts = Self.timeStamp()
            let timestamped = "[\(ts)] \(msg)"
            NSLog("[QR Diag] %@", msg)
            let line = timestamped + "\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: Self.logFileURL)
                }
            }
            DispatchQueue.main.async { autoTestLines.append(timestamped) }
        }

        private static func clearLogFile() {
            try? FileManager.default.removeItem(at: logFileURL)
        }

        private static func timeStamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: Date())
        }

        // MARK: - QR Display

        private var qrDisplay: some View {
            VStack(spacing: 4) {
                let content = qrTestLevel.sampleContent
                Text("\(content.count) chars, EC-\(ecLevel), \(qrTestLevel.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let image = generateQRCode(from: content, correctionLevel: ecLevel) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .background(Color.white)
                        .cornerRadius(4)
                } else {
                    Text("QR generation failed")
                        .foregroundColor(.red)
                }
            }
        }

        // MARK: - Controls

        private var complexityPicker: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QrTestLevel.allCases, id: \.self) { level in
                        Button(action: {
                            qrTestLevel = level
                            stats.reset()
                        }) {
                            Text(level.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(qrTestLevel == level ? Color.accentColor : Color(.systemGray5))
                                .foregroundColor(qrTestLevel == level ? .white : .primary)
                                .cornerRadius(16)
                        }
                    }
                }
            }
        }

        private var ecPicker: some View {
            HStack(spacing: 6) {
                ForEach(["L", "M", "Q", "H"], id: \.self) { ec in
                    Button(action: {
                        ecLevel = ec
                        stats.reset()
                    }) {
                        Text("EC-\(ec)")
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(ecLevel == ec ? Color.accentColor : Color(.systemGray5))
                            .foregroundColor(ecLevel == ec ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
        }

        // MARK: - Stats Card

        private var statsCard: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Detection Stats")
                    .font(.headline)

                Group {
                    statRow("Camera", "Front (selfie)")
                    statRow("Resolution", stats.resolution)
                    statRow("Frames", "\(stats.frameCount)")
                    statRow("Detections", "\(stats.detectionCount)")
                    statRow("Rate", stats.detectionRate)
                    if !stats.lastDetected.isEmpty {
                        let truncated = stats.lastDetected.prefix(60)
                        statRow("Last", String(truncated) + (stats.lastDetected.count > 60 ? "..." : ""))
                    }
                    if let time = stats.lastDetectedTime {
                        statRow("When", "\(String(format: "%.1f", Date().timeIntervalSince(time)))s ago")
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }

        private func statRow(_ label: String, _ value: String) -> some View {
            HStack {
                Text("\(label):")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 90, alignment: .leading)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
            }
        }

        // MARK: - Camera Status

        private var cameraStatus: some View {
            Group {
                if !cameraGranted, permissionsChecked {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("Camera permission required")
                            .font(.callout)
                        Button("Grant Permission") {
                            requestPermissions()
                        }
                    }
                    .padding()
                } else if cameraGranted {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                            .foregroundColor(.green)
                        Text("Front camera scanning active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }

        // MARK: - Permissions

        private func requestPermissions() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cameraGranted = true
                permissionsChecked = true
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        cameraGranted = granted
                        permissionsChecked = true
                    }
                }
            default:
                cameraGranted = false
                permissionsChecked = true
            }
        }

        // MARK: - Scanner

        private func startScanner() {
            scanner.start(stats: stats) { code in
                NSLog("[QRDiag] Detected: %@", String(code.prefix(50)))
            }
        }

        // MARK: - QR Generation

        private func generateQRCode(from string: String, correctionLevel: String = "M") -> UIImage? {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(string.utf8)
            filter.correctionLevel = correctionLevel

            guard let outputImage = filter.outputImage else { return nil }
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)

            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
    }

    #Preview {
        NavigationView {
            QRDiagnosticView()
        }
    }
#endif
