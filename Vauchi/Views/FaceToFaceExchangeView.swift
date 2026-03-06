// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FaceToFaceExchangeView.swift
// Split-screen exchange: cycling QR codes on top, front camera scanner on bottom.
// Both users hold phones face-to-face for simultaneous contact exchange.
// The core Rust library drives the multi-stage protocol — this view is a pure display shell.

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import VauchiMobile

/// QR code colors: gray reduces screen glare at close face-to-face distance.
private let qrForegroundColor = CIColor(red: 64.0 / 255, green: 64.0 / 255, blue: 64.0 / 255) // #404040
private let qrBackgroundColor = CIColor(red: 224.0 / 255, green: 224.0 / 255, blue: 224.0 / 255) // #E0E0E0

/// Warm beige background: soft, non-reflective.
private let exchangeBackgroundColor = Color(red: 0.96, green: 0.94, blue: 0.92) // #F5F0EB

private enum ScanQuality {
    case good // Green — QR being scanned right now
    case fair // Orange — scanned recently but stale
    case none // Red — no scan detected

    var color: Color {
        switch self {
        case .good: Color(red: 0.298, green: 0.686, blue: 0.314) // #4CAF50
        case .fair: Color(red: 1.0, green: 0.596, blue: 0.0) // #FF9800
        case .none: Color(red: 0.957, green: 0.263, blue: 0.212) // #F44336
        }
    }

    var label: String {
        switch self {
        case .good: "Scanning"
        case .fair: "Weak signal"
        case .none: "No QR detected"
        }
    }
}

struct FaceToFaceExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared
    var switchToContacts: (() -> Void)?

    // MARK: - Multi-stage exchange state

    @State private var multiStageQrImage: UIImage?
    @State private var protocolState: MobileProtocolState = .idle
    @State private var qrCycleTimer: Timer?
    @State private var statePollTimer: Timer?
    @State private var scanQualityTimer: Timer?
    @State private var previousBrightness: CGFloat = 0.5
    @State private var graceCompleted = false
    @State private var lastScanTimestamp: Date?
    @State private var scanQuality: ScanQuality = .none

    // MARK: - Shared state

    @State private var useFrontCamera = true
    @State private var cameraGranted = false
    @State private var permissionsChecked = false
    @StateObject private var qrScanner = HeadlessQrScanner()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !cameraGranted, permissionsChecked {
                    permissionNeededContent
                } else {
                    multiStageContent
                }
            }
            .navigationTitle(localizationService.t("nav.exchange"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        cancelAndDismiss()
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
                previousBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 1.0
                requestPermissions()
                startScannerIfReady()
                startMultiStageSession()
                startScanQualityTimer()
            }
            .onDisappear {
                UIScreen.main.brightness = previousBrightness
                qrScanner.stop()
                stopAllTimers()
                viewModel.cancelMultiStageExchange()
            }
            .onChange(of: cameraGranted) { _ in
                startScannerIfReady()
            }
            .onChange(of: useFrontCamera) { front in
                if cameraGranted {
                    qrScanner.switchCamera(toFront: front)
                }
            }
        }
    }

    // MARK: - Multi-Stage Content

    private var multiStageContent: some View {
        VStack(spacing: 0) {
            switch protocolState {
            case .idle, .advertising:
                multiStageQrDisplay(statusText: "Waiting for peer...", showProgress: false)

            case .discovered:
                multiStageQrDisplay(statusText: "Peer found! Exchanging...", showProgress: true)

            case let .transferring(_, _, chunksReceived, peerChunksTotal):
                multiStageQrDisplay(
                    statusText: transferProgressText(received: chunksReceived, total: peerChunksTotal),
                    showProgress: true
                )

            case .verifying, .confirming:
                multiStageQrDisplay(statusText: "Verifying exchange...", showProgress: true)

            case .complete:
                if !graceCompleted {
                    multiStageQrDisplay(statusText: "Completing exchange...", showProgress: true)
                } else {
                    multiStageSuccessContent
                }

            case let .failed(reason):
                multiStageFailedContent(reason: reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(exchangeBackgroundColor)
    }

    private func multiStageQrDisplay(statusText: String, showProgress: Bool) -> some View {
        VStack(spacing: 0) {
            // === TOP: QR code with generous margins ===
            Spacer().frame(height: 8)

            if let image = multiStageQrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .background(Color(red: 224.0 / 255, green: 224.0 / 255, blue: 224.0 / 255))
                    .cornerRadius(12)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.98)
                    .accessibilityLabel("Exchange QR code")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 224.0 / 255, green: 224.0 / 255, blue: 224.0 / 255))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.98)
                    .overlay(ProgressView())
            }

            Spacer()

            // === MIDDLE: Instruction text ===
            Text("Point camera at other phone's QR")
                .font(.callout)
                .foregroundColor(Color(white: 0.4))

            Spacer().frame(height: 16)

            // === BOTTOM: Camera preview + status indicators ===
            HStack(alignment: .bottom, spacing: 12) {
                // Small camera preview square
                if cameraGranted {
                    CameraPreviewView(previewLayer: qrScanner.previewLayer)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(white: 0.6), lineWidth: 2)
                        )
                }

                // Status indicators
                VStack(alignment: .leading, spacing: 4) {
                    if showProgress {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.27))
                        }
                    } else {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.27))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 8)

            // === STATUS BAR: scan quality indicator ===
            HStack(spacing: 8) {
                Circle()
                    .fill(scanQuality.color)
                    .frame(width: 10, height: 10)
                Text(scanQuality.label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(Color(white: 0.27))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 0.93, green: 0.91, blue: 0.89)) // Slightly darker beige

            Spacer().frame(height: 4)
        }
    }

    private var multiStageSuccessContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Contact exchanged!")
                .font(.title2)
                .fontWeight(.semibold)

            Button(action: { cancelAndDismiss() }) {
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
    }

    private func multiStageFailedContent(reason: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Exchange failed")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.red)

            Text(reason)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { retryMultiStageExchange() }) {
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
    }

    // MARK: - Multi-Stage Actions

    private func startMultiStageSession() {
        // TODO: Replace placeholder with actual serialized contact card from identity
        let localCard = Data("Vauchi User".utf8)
        viewModel.startMultiStageExchange(localCard: localCard)
        protocolState = .idle
        graceCompleted = false
        multiStageQrImage = nil
        startQrCycleTimer()
        startStatePollTimer()
    }

    private func startQrCycleTimer() {
        qrCycleTimer?.invalidate()
        qrCycleTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            guard let payload = viewModel.getMultiStageDisplayQr() else {
                // Core returned nil — grace period expired or not started.
                if case .complete = protocolState {
                    graceCompleted = true
                }
                stopQrCycleTimer()
                return
            }
            multiStageQrImage = generateQRCode(from: payload.data, correctionLevel: payload.errorCorrection)
        }
    }

    private func startStatePollTimer() {
        statePollTimer?.invalidate()
        statePollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            let newState = viewModel.getMultiStageState()
            protocolState = newState

            // Only stop on Failed — Complete still needs the QR cycle timer
            // running so core can display grace-period QR codes for the slower peer.
            switch newState {
            case .failed:
                stopQrCycleTimer()
                stopStatePollTimer()
            default:
                break
            }
        }
    }

    private func retryMultiStageExchange() {
        viewModel.cancelMultiStageExchange()
        stopAllTimers()
        qrScanner.stop()
        startMultiStageSession()
        startScannerIfReady()
    }

    private func cancelAndDismiss() {
        viewModel.cancelMultiStageExchange()
        switchToContacts?()
    }

    private func stopQrCycleTimer() {
        qrCycleTimer?.invalidate()
        qrCycleTimer = nil
    }

    private func stopStatePollTimer() {
        statePollTimer?.invalidate()
        statePollTimer = nil
    }

    private func stopAllTimers() {
        stopQrCycleTimer()
        stopStatePollTimer()
        scanQualityTimer?.invalidate()
        scanQualityTimer = nil
    }

    private func startScanQualityTimer() {
        scanQualityTimer?.invalidate()
        scanQualityTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            guard let lastScan = lastScanTimestamp else {
                scanQuality = .none
                return
            }
            let elapsed = Date().timeIntervalSince(lastScan)
            if elapsed < 0.5 {
                scanQuality = .good
            } else if elapsed < 2.0 {
                scanQuality = .fair
            } else {
                scanQuality = .none
            }
        }
    }

    private func transferProgressText(received: UInt8, total: UInt8) -> String {
        if total > 0 {
            return "Receiving \(received)/\(total) chunks..."
        }
        return "Transferring data..."
    }

    // MARK: - Multi-Stage Scanner

    private func handleMultiStageScannedCode(_ code: String) {
        lastScanTimestamp = Date()
        let newState = viewModel.processMultiStageQr(raw: code)
        protocolState = newState
    }

    // MARK: - Permission Needed State

    private var permissionNeededContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Camera Required")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Camera is needed to scan QR codes for contact exchange.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: requestPermissions) {
                Text("Grant Permission")
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

    // MARK: - Actions

    private func startScannerIfReady() {
        guard cameraGranted else {
            return
        }
        qrScanner.start(useFrontCamera: useFrontCamera) { code in
            handleMultiStageScannedCode(code)
        }
    }

    // MARK: - QR Generation

    /// Generate a gray QR code image. Gray reduces screen glare at close face-to-face distance.
    private func generateQRCode(from string: String, correctionLevel: String = "L") -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = correctionLevel

        guard let qrImage = filter.outputImage else { return nil }

        // Apply gray colors using CIFalseColor filter
        let colorFilter = CIFilter.falseColor()
        colorFilter.inputImage = qrImage
        colorFilter.color0 = qrForegroundColor // Dark gray for QR modules
        colorFilter.color1 = qrBackgroundColor // Light gray for background

        guard let coloredImage = colorFilter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = coloredImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Camera Preview (SwiftUI wrapper for AVCaptureVideoPreviewLayer)

/// UIView subclass that keeps the preview layer sized to its bounds.
class PreviewContainerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            guard let layer = previewLayer else { return }
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

/// Small camera preview that shows what the scanner sees.
struct CameraPreviewView: UIViewRepresentable {
    var previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context _: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.backgroundColor = .black
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context _: Context) {
        uiView.previewLayer = previewLayer
    }
}

// MARK: - QR Scanner with Preview

/// Runs AVCaptureSession + AVCaptureMetadataOutput with an optional visible preview layer.
class HeadlessQrScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    private var captureSession: AVCaptureSession?
    private var currentPosition: AVCaptureDevice.Position = .unspecified
    private var onQrScanned: ((String) -> Void)?
    private var lastScannedCode: String?
    private var lastScanTime: Date?
    /// Preview layer — used both to keep metadata pipeline active and for the small camera preview.
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func start(useFrontCamera: Bool, onQrScanned: @escaping (String) -> Void) {
        self.onQrScanned = onQrScanned
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        initializeCamera(position: position)
    }

    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        previewLayer = nil
        currentPosition = .unspecified
    }

    func switchCamera(toFront: Bool) {
        let newPosition: AVCaptureDevice.Position = toFront ? .front : .back
        guard newPosition != currentPosition else { return }
        initializeCamera(position: newPosition)
    }

    private func initializeCamera(position: AVCaptureDevice.Position) {
        captureSession?.stopRunning()

        let session = AVCaptureSession()
        // 480p — best decode rate at close face-to-face distance
        session.sessionPreset = .vga640x480

        var device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        var actualPosition = position
        if device == nil {
            let fallback: AVCaptureDevice.Position = position == .front ? .back : .front
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: fallback)
            actualPosition = fallback
        }

        guard let cam = device, let input = try? AVCaptureDeviceInput(device: cam) else { return }

        // Enable continuous auto-focus for better QR readability
        if cam.isFocusModeSupported(.continuousAutoFocus) {
            try? cam.lockForConfiguration()
            cam.focusMode = .continuousAutoFocus
            cam.unlockForConfiguration()
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
        }

        // Preview layer — drives both the small camera preview and keeps the metadata pipeline active
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview

        captureSession = session
        currentPosition = actualPosition

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(_: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from _: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadataObject.stringValue
        else {
            return
        }

        // Short debounce: multi-stage protocol needs repeated scans of the
        // same QR to advance through stages. 100ms prevents duplicate processing
        // of the same camera frame while allowing rapid re-scanning.
        if let lastCode = lastScannedCode,
           let lastTime = lastScanTime,
           lastCode == code,
           Date().timeIntervalSince(lastTime) < 0.1 {
            return
        }

        lastScannedCode = code
        lastScanTime = Date()
        onQrScanned?(code)
    }

    deinit {
        captureSession?.stopRunning()
    }
}

#Preview {
    FaceToFaceExchangeView(switchToContacts: {})
        .environmentObject(VauchiViewModel())
}
