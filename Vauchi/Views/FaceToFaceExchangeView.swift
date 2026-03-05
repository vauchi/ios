// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FaceToFaceExchangeView.swift
// Split-screen exchange: QR code on top, front camera scanner on bottom.
// Both users hold phones face-to-face for simultaneous contact exchange.

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Flow state for the face-to-face exchange
enum FaceToFaceFlowState: Equatable {
    case scanning
    case completing
    case success(contactName: String)
    case failed(error: String)
}

struct FaceToFaceExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    @State private var exchangeData: ExchangeDataInfo?
    @State private var qrImage: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    @State private var flowState: FaceToFaceFlowState = .scanning
    @State private var useFrontCamera = true
    @State private var proximityConfirmed = false
    @State private var emitTask: Task<Void, Never>?
    @State private var cameraGranted = false
    @State private var micGranted = false
    @State private var permissionsChecked = false

    private var allPermissionsGranted: Bool {
        cameraGranted && micGranted
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !allPermissionsGranted, permissionsChecked {
                    permissionNeededContent
                } else {
                    switch flowState {
                    case .scanning:
                        scanningContent

                    case .completing:
                        completingContent

                    case let .success(contactName):
                        successContent(contactName: contactName)

                    case let .failed(error):
                        failedContent(error: error)
                    }
                }
            }
            .navigationTitle(localizationService.t("nav.exchange"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        stopEmitting()
                        viewModel.stopProximityVerification()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { useFrontCamera.toggle() }) {
                        Image(systemName: "camera.rotate")
                            .accessibilityLabel(useFrontCamera ? "Switch to rear camera" : "Switch to front camera")
                    }
                }
            }
            .onAppear {
                requestPermissions()
            }
            .onDisappear {
                stopTimer()
                stopEmitting()
                viewModel.stopProximityVerification()
            }
        }
    }

    // MARK: - Scanning State (QR with camera overlay in center)

    private var scanningContent: some View {
        VStack(spacing: 12) {
            Spacer()

            if isLoading {
                ProgressView()
            } else if hasError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(localizationService.t("exchange.qr_error"))
                        .font(.caption)
                    Button("Retry") { loadExchangeData() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            } else if let image = qrImage {
                // QR code with camera square in the center
                ZStack {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                        .background(Color.white)
                        .cornerRadius(8)
                        .accessibilityLabel("Your contact exchange QR code")

                    // Hidden camera scanner (no visible preview, just QR analysis)
                    FaceToFaceCameraPreview(
                        useFrontCamera: useFrontCamera,
                        onQrScanned: { code in
                            handleScannedCode(code)
                        }
                    )
                    .frame(width: 50, height: 50)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 2)

                HStack(spacing: 12) {
                    // Timer
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(localizationService.t("exchange.expires_in", args: ["time": formatTime(timeRemaining)]))
                            .font(.caption2)
                    }
                    .foregroundColor(timeRemaining < 60 ? .orange : .secondary)

                    // Refresh
                    Button(action: { loadExchangeData() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(timeRemaining > 240)
                }

                // Proximity indicator
                if viewModel.proximitySupported {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.circle")
                            .font(.caption2)
                            .foregroundColor(proximityConfirmed ? .green : .blue)
                        Text(proximityConfirmed ? "Proximity verified" : "Ultrasonic active")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Point camera at other phone's QR")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    // MARK: - Completing State

    private var completingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Completing exchange...")
                .font(.body)
                .foregroundColor(.secondary)
            if proximityConfirmed {
                Text("Proximity verified")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success State

    private func successContent(contactName: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Contact exchanged!")
                .font(.title2)
                .fontWeight(.semibold)

            if proximityConfirmed {
                Text("Proximity verified via ultrasonic")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Text("Successfully added \(contactName)")
                .font(.body)
                .foregroundColor(.secondary)

            Button(action: resetToScanning) {
                Text(localizationService.t("action.done"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Failed State

    private func failedContent(error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Exchange failed")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.red)

            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: resetToScanning) {
                Text(localizationService.t("action.retry"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permission Needed State

    private var permissionNeededContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Camera & Microphone Required")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Camera scans QR codes for contact exchange.\nMicrophone verifies proximity via ultrasonic.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: requestPermissions) {
                Text("Grant Permissions")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permissions

    private func requestPermissions() {
        let group = DispatchGroup()

        // Camera
        group.enter()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraGranted = true
            group.leave()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraGranted = granted }
                group.leave()
            }
        default:
            cameraGranted = false
            group.leave()
        }

        // Microphone
        group.enter()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
            group.leave()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { micGranted = granted }
                group.leave()
            }
        default:
            micGranted = false
            group.leave()
        }

        group.notify(queue: .main) {
            permissionsChecked = true
            if allPermissionsGranted {
                loadExchangeData()
                startEmitting()
            }
        }
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        guard code.hasPrefix("wb://"), flowState == .scanning else { return }

        flowState = .completing
        stopEmitting()

        // Ultrasonic proximity check on background thread (non-blocking, fire-and-forget)
        if viewModel.proximitySupported {
            let challenge = ExchangeDataInfo.extractAudioChallenge(from: code)
            if let challenge {
                let vm = viewModel
                DispatchQueue.global(qos: .userInitiated).async {
                    let response = vm.listenForProximityResponse(timeoutMs: 3000)
                    if let resp = response, resp == challenge {
                        DispatchQueue.main.async {
                            proximityConfirmed = true
                        }
                        print("FaceToFace: Ultrasonic proximity confirmed")
                    }
                    vm.stopProximityVerification()
                }
            }
        }

        // Complete exchange immediately (don't wait for proximity)
        Task {
            do {
                let result = try await viewModel.completeExchange(qrData: code)
                await MainActor.run {
                    if result.success {
                        flowState = .success(contactName: result.contactName)
                    } else {
                        flowState = .failed(error: result.errorMessage ?? "Exchange failed")
                    }
                }
            } catch {
                await MainActor.run {
                    flowState = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    private func resetToScanning() {
        flowState = .scanning
        proximityConfirmed = false
        startEmitting()
    }

    private func loadExchangeData() {
        isLoading = true
        hasError = false
        stopTimer()

        do {
            exchangeData = try viewModel.generateExchangeData()
            if let data = exchangeData {
                qrImage = generateQRCode(from: data.qrData)
                timeRemaining = data.timeRemaining
                startTimer()
            }
            hasError = exchangeData == nil
        } catch {
            hasError = true
        }

        isLoading = false
    }

    // MARK: - Ultrasonic Emit Loop

    private func startEmitting() {
        guard viewModel.proximitySupported, let challenge = exchangeData?.audioChallenge else { return }
        emitTask?.cancel()
        emitTask = Task {
            while !Task.isCancelled {
                // Run blocking emit on background thread
                let vm = viewModel
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        _ = vm.emitProximityChallenge(challenge)
                        continuation.resume()
                    }
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func stopEmitting() {
        emitTask?.cancel()
        emitTask = nil
        viewModel.stopProximityVerification()
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                loadExchangeData()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Camera Preview (supports front/rear switching)

struct FaceToFaceCameraPreview: UIViewRepresentable {
    let useFrontCamera: Bool
    let onQrScanned: (String) -> Void

    func makeUIView(context: Context) -> FaceToFaceCameraView {
        let view = FaceToFaceCameraView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: FaceToFaceCameraView, context _: Context) {
        uiView.switchCamera(toFront: useFrontCamera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onQrScanned: onQrScanned)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onQrScanned: (String) -> Void
        private var lastScannedCode: String?
        private var lastScanTime: Date?

        init(onQrScanned: @escaping (String) -> Void) {
            self.onQrScanned = onQrScanned
        }

        func metadataOutput(_: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from _: AVCaptureConnection) {
            guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = metadataObject.stringValue
            else { return }

            // Debounce
            if let lastCode = lastScannedCode,
               let lastTime = lastScanTime,
               lastCode == code,
               Date().timeIntervalSince(lastTime) < 3.0 {
                return
            }

            lastScannedCode = code
            lastScanTime = Date()

            DispatchQueue.main.async {
                self.onQrScanned(code)
            }
        }
    }
}

class FaceToFaceCameraView: UIView {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentPosition: AVCaptureDevice.Position = .unspecified
    private var metadataOutput: AVCaptureMetadataOutput?
    private var desiredPosition: AVCaptureDevice.Position = .front
    private var isSettingUp = false

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds

        // Start camera once we have non-zero bounds
        if captureSession == nil, !isSettingUp, bounds.width > 0, bounds.height > 0 {
            setupCamera(position: desiredPosition)
        }
    }

    func switchCamera(toFront: Bool) {
        let newPosition: AVCaptureDevice.Position = toFront ? .front : .back
        desiredPosition = newPosition
        guard newPosition != currentPosition else { return }
        if captureSession != nil {
            setupCamera(position: newPosition)
        }
        // If captureSession is nil, layoutSubviews will pick up desiredPosition
    }

    private func setupCamera(position: AVCaptureDevice.Position) {
        isSettingUp = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            initializeCamera(position: position)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.initializeCamera(position: position)
                    }
                } else {
                    DispatchQueue.main.async { self?.isSettingUp = false }
                }
            }
        default:
            isSettingUp = false
            showPermissionDenied()
        }
    }

    private func initializeCamera(position: AVCaptureDevice.Position) {
        // Stop existing session
        captureSession?.stopRunning()
        previewLayer?.removeFromSuperlayer()

        let session = AVCaptureSession()
        session.sessionPreset = .hd1920x1080

        // Try requested position first, fall back to other if unavailable
        var device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        var actualPosition = position
        if device == nil {
            let fallback: AVCaptureDevice.Position = position == .front ? .back : .front
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: fallback)
            actualPosition = fallback
            print("FaceToFace: \(position) camera unavailable, falling back to \(fallback)")
        }

        guard let cam = device, let input = try? AVCaptureDeviceInput(device: cam) else {
            isSettingUp = false
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
        }
        metadataOutput = output

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.addSublayer(preview)

        captureSession = session
        previewLayer = preview
        currentPosition = actualPosition
        isSettingUp = false

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func showPermissionDenied() {
        let label = UILabel()
        label.text = "Camera access required.\nPlease enable in Settings."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
        backgroundColor = .black
    }

    deinit {
        captureSession?.stopRunning()
    }
}

#Preview {
    FaceToFaceExchangeView()
        .environmentObject(VauchiViewModel())
}
