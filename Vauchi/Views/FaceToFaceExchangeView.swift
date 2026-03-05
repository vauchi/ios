// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FaceToFaceExchangeView.swift
// Split-screen exchange: QR code on top, front camera scanner on bottom.
// Both users hold phones face-to-face for simultaneous contact exchange.

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Flow state for the bidirectional face-to-face exchange
enum FaceToFaceFlowState: Equatable {
    case scanning
    case scanned(peerName: String)
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
    @State private var cameraGranted = false
    @State private var permissionsChecked = false
    @StateObject private var qrScanner = HeadlessQrScanner()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !cameraGranted, permissionsChecked {
                    permissionNeededContent
                } else {
                    switch flowState {
                    case .scanning:
                        scanningContent

                    case let .scanned(peerName):
                        qrWithStatusContent(status: "Found \(peerName)!")

                    case .completing:
                        qrWithStatusContent(status: "Exchanging contacts...")

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
                        viewModel.clearActiveSession()
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
                startScannerIfReady()
            }
            .onDisappear {
                qrScanner.stop()
                stopTimer()
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
                // QR code — full width for easy scanning by peer
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.horizontal, 2)
                    .accessibilityLabel("Your contact exchange QR code")

                // Camera scanner runs headless (no UIView) — just QR metadata detection

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

                Text("Point camera at other phone's QR")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    // MARK: - QR With Status (intermediate states — QR stays visible for peer)

    private func qrWithStatusContent(status: String) -> some View {
        VStack(spacing: 4) {
            // Status at top, compact
            HStack(spacing: 6) {
                ProgressView()
                Text(status)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .padding(.top, 8)

            // QR stays FULL WIDTH so peer can still scan
            if let image = qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .background(Color.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
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
            loadExchangeData()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraGranted = granted
                    permissionsChecked = true
                    if granted { loadExchangeData() }
                }
            }
        default:
            cameraGranted = false
            permissionsChecked = true
        }
    }

    // MARK: - Actions

    private func startScannerIfReady() {
        guard cameraGranted else { return }
        qrScanner.start(useFrontCamera: useFrontCamera) { code in
            handleScannedCode(code)
        }
    }

    private func handleScannedCode(_ code: String) {
        guard code.hasPrefix("wb://"), flowState == .scanning else { return }

        NSLog("[Exchange] Scanned QR, processing on held session...")

        // Step 1: Process the scanned QR on the held session
        let peerName: String
        do {
            peerName = try viewModel.processScannedQr(qrData: code)
        } catch {
            NSLog("[Exchange] processQr failed: \(error.localizedDescription)")
            flowState = .failed(error: "Invalid QR: \(error.localizedDescription)")
            return
        }
        NSLog("[Exchange] Peer recognized, completing exchange...")
        flowState = .scanned(peerName: peerName)

        // Step 2: Complete exchange — mutual QR scan proves proximity
        Task {
            flowState = .completing
            do {
                let result = try await viewModel.completeExchangeAfterCoordination()
                NSLog("[Exchange] Exchange completed: success=\(result.success)")
                if result.success {
                    flowState = .success(contactName: result.contactName)
                } else {
                    flowState = .failed(error: result.errorMessage ?? "Exchange failed")
                }
            } catch {
                NSLog("[Exchange] Exchange FAILED: \(error.localizedDescription)")
                flowState = .failed(error: error.localizedDescription)
            }
        }
    }

    private func resetToScanning() {
        viewModel.clearActiveSession()
        flowState = .scanning
        loadExchangeData()
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
        filter.correctionLevel = "L"

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
