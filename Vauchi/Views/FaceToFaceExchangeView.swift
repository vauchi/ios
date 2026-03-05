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

struct FaceToFaceExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    // MARK: - Multi-stage exchange state

    @State private var multiStageQrImage: UIImage?
    @State private var protocolState: MobileProtocolState = .idle
    @State private var qrCycleTimer: Timer?
    @State private var statePollTimer: Timer?
    @State private var previousBrightness: CGFloat = 0.5

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
                multiStageSuccessContent

            case let .failed(reason):
                multiStageFailedContent(reason: reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    private func multiStageQrDisplay(statusText: String, showProgress: Bool) -> some View {
        VStack(spacing: 8) {
            // Status bar
            HStack(spacing: 6) {
                if showProgress {
                    ProgressView()
                }
                Text(statusText)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .padding(.top, 8)

            // Cycling QR code — full width for easy scanning by peer
            if let image = multiStageQrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.horizontal, 2)
                    .accessibilityLabel("Exchange QR code")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            }

            Text("Point camera at other phone's QR")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
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
        let localCard = "Vauchi User".data(using: .utf8)!
        viewModel.startMultiStageExchange(localCard: localCard)
        protocolState = .idle
        startQrCycleTimer()
        startStatePollTimer()
    }

    private func startQrCycleTimer() {
        qrCycleTimer?.invalidate()
        qrCycleTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            guard let payload = viewModel.getMultiStageDisplayQr() else {
                // Core returned nil — grace period expired or not started.
                // Stop QR cycling but keep state poll alive for UI updates.
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
        multiStageQrImage = nil
        startMultiStageSession()
    }

    private func cancelAndDismiss() {
        viewModel.cancelMultiStageExchange()
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
    }

    private func transferProgressText(received: UInt8, total: UInt8) -> String {
        if total > 0 {
            return "Receiving \(received)/\(total) chunks..."
        }
        return "Transferring data..."
    }

    // MARK: - Multi-Stage Scanner

    private func handleMultiStageScannedCode(_ code: String) {
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

    private func generateQRCode(from string: String, correctionLevel: String = "L") -> UIImage? {
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

// MARK: - Headless QR Scanner (no UIView — prevents camera preview leak)

/// Runs AVCaptureSession + AVCaptureMetadataOutput without any view hierarchy.
/// This avoids the GPU-backed camera layer that punches through SwiftUI opacity.
class HeadlessQrScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    private var captureSession: AVCaptureSession?
    private var currentPosition: AVCaptureDevice.Position = .unspecified
    private var onQrScanned: ((String) -> Void)?
    private var lastScannedCode: String?
    private var lastScanTime: Date?

    func start(useFrontCamera: Bool, onQrScanned: @escaping (String) -> Void) {
        self.onQrScanned = onQrScanned
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        initializeCamera(position: position)
    }

    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
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
        session.sessionPreset = .hd1280x720

        var device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        var actualPosition = position
        if device == nil {
            let fallback: AVCaptureDevice.Position = position == .front ? .back : .front
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: fallback)
            actualPosition = fallback
        }

        guard let cam = device, let input = try? AVCaptureDeviceInput(device: cam) else { return }

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
    FaceToFaceExchangeView()
        .environmentObject(VauchiViewModel())
}
