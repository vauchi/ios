// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FaceToFaceExchangeView.swift
// Split-screen exchange: cycling QR codes on top, front camera scanner on bottom.
// Both users hold phones face-to-face for simultaneous contact exchange.
// Core drives the multi-stage protocol via the G4 event API — this view is a
// pure renderer that forwards scanned QRs and reflects `MultiStageSessionListener`
// callbacks.

import AVFoundation
import CoreUIModels
import SwiftUI
import VauchiPlatform

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

/// Observable bridge for the core multi-stage event API. Core invokes
/// `MultiStageSessionListener` methods on the `vauchi-exchange-cycle`
/// thread; each callback hops to the main actor before mutating
/// `@Published` state so SwiftUI observes a coherent snapshot.
@MainActor
final class MultiStageExchangeState: ObservableObject {
    @Published var protocolState: MobileProtocolState = .idle
    @Published var qrPayload: MobileQrPayload?
    @Published var finalizedContactName: String?
    @Published var sessionEnded: Bool = false
}

/// UniFFI callback target. A final class (not a struct) because the binding
/// protocol requires `AnyObject`. The view owns this via `@StateObject` so
/// the reference stays alive for the FFI vtable.
private final class MultiStageListener: MultiStageSessionListener {
    private let state: MultiStageExchangeState

    init(state: MultiStageExchangeState) {
        self.state = state
    }

    func onQrPayload(payload: MobileQrPayload) {
        Task { @MainActor [state] in state.qrPayload = payload }
    }

    func onStateChanged(state newState: MobileProtocolState) {
        Task { @MainActor [state] in state.protocolState = newState }
    }

    func onFinalized(contactName: String) {
        Task { @MainActor [state] in state.finalizedContactName = contactName }
    }

    func onSessionEnded() {
        Task { @MainActor [state] in state.sessionEnded = true }
    }
}

struct FaceToFaceExchangeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @ObservedObject private var localizationService = LocalizationService.shared
    var switchToContacts: (() -> Void)?

    // MARK: - Multi-stage exchange state (listener-driven)

    @StateObject private var exchange = MultiStageExchangeState()
    @State private var multiStageQrImage: UIImage?
    /// Track last QR data so we only regenerate the bitmap when bytes change.
    @State private var lastQrData: String?
    @State private var previousBrightness: CGFloat = 0.5

    /// Retained so the FFI vtable keeps pointing at a live listener. Dropped
    /// in `cancelAndDismiss` / `retryMultiStageExchange` after
    /// `session.cancel()` joins the cycle thread.
    @State private var listener: MultiStageSessionListener?

    // MARK: - Scan-quality timer (presentational only, not exchange clock)

    @State private var scanQualityTimer: Timer?
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
                    .accessibilityIdentifier("exchange.back")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { useFrontCamera.toggle() }) {
                        Image(systemName: "camera.rotate")
                            .accessibilityLabel(useFrontCamera ? "Switch to rear camera" : "Switch to front camera")
                    }
                    .accessibilityIdentifier("exchange.camera_toggle")
                }
            }
            .onAppear {
                previousBrightness = UIScreen.main.brightness
                // 65% brightness — matches Android. Higher values overexpose the
                // device's own front camera, preventing it from scanning the peer's QR.
                // Gray QR colors (#404040 on #E0E0E0) compensate for reduced luminance.
                UIScreen.main.brightness = 0.65
                // Prevent screen lock during exchange — QR must stay visible.
                UIApplication.shared.isIdleTimerDisabled = true
                requestPermissions()
                startScannerIfReady()
                startMultiStageSession()
                startScanQualityTimer()
            }
            .onDisappear {
                UIScreen.main.brightness = previousBrightness
                UIApplication.shared.isIdleTimerDisabled = false
                qrScanner.stop()
                stopScanQualityTimer()
                viewModel.cancelMultiStageExchange()
                listener = nil
            }
            .onChange(of: exchange.qrPayload?.data) { _ in
                guard let payload = exchange.qrPayload else { return }
                if payload.data != lastQrData {
                    lastQrData = payload.data
                    multiStageQrImage = generateQRCode(
                        from: payload.data,
                        correctionLevel: payload.errorCorrection
                    )
                }
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
            switch exchange.protocolState {
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

            case .complete, .finalized:
                // Stay on the QR while core keeps broadcasting the COMBO frame
                // for the grace window. Once the cycle thread signals
                // `on_session_ended`, flip to the success screen.
                if exchange.sessionEnded {
                    multiStageSuccessContent
                } else {
                    multiStageQrDisplay(statusText: "Keep pointing at other phone...", showProgress: true)
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
            Spacer().frame(height: 8)
            exchangeQrImage
            Spacer()
            Text("Point camera at other phone's QR")
                .font(.callout)
                .foregroundColor(Color(white: 0.4))
            Spacer().frame(height: 16)
            exchangeBottomBar(statusText: statusText, showProgress: showProgress)
            Spacer().frame(height: 8)
            exchangeScanQualityBar
            Spacer().frame(height: 4)
        }
    }

    @ViewBuilder
    private var exchangeQrImage: some View {
        if let image = multiStageQrImage {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .padding(8)
                .background(Color(red: 224.0 / 255, green: 224.0 / 255, blue: 224.0 / 255))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.98)
                .accessibilityLabel("Exchange QR code")
        } else {
            RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.mdLg))
                .fill(Color(red: 224.0 / 255, green: 224.0 / 255, blue: 224.0 / 255))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.98)
                .overlay(ProgressView())
        }
    }

    private func exchangeBottomBar(statusText: String, showProgress: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            if cameraGranted {
                CameraPreviewView(previewLayer: qrScanner.previewLayer)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.mdLg)))
                    .overlay(
                        RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.mdLg))
                            .stroke(Color(white: 0.6), lineWidth: 2)
                    )
            }
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
    }

    private var exchangeScanQualityBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(scanQuality.color)
                .frame(width: 10, height: 10)
            Text(scanQuality.label)
                .font(Font.caption2.weight(.medium))
                .foregroundColor(Color(white: 0.27))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.93, green: 0.91, blue: 0.89))
    }

    private var multiStageSuccessContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Contact exchanged!")
                .font(Font.title2.weight(.semibold))

            if let contactName = exchange.finalizedContactName {
                Text("\(contactName) has been added.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Button(action: { cancelAndDismiss() }) {
                Text(localizationService.t("action.done"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
            .accessibilityIdentifier("exchange.done")
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
                .font(Font.title2.weight(.semibold))
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
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
            .accessibilityIdentifier("exchange.retry")
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Multi-Stage Actions

    /// Spin up a new session, register the listener, and hand control to
    /// core's cycle thread. No frontend timers — state updates arrive via
    /// `MultiStageExchangeState`.
    private func startMultiStageSession() {
        // Reset per-session view state.
        exchange.protocolState = .idle
        exchange.qrPayload = nil
        exchange.finalizedContactName = nil
        exchange.sessionEnded = false
        multiStageQrImage = nil
        lastQrData = nil

        let newListener = MultiStageListener(state: exchange)
        listener = newListener
        _ = viewModel.startMultiStageExchange(listener: newListener)
    }

    private func retryMultiStageExchange() {
        viewModel.cancelMultiStageExchange()
        listener = nil
        qrScanner.stop()
        startMultiStageSession()
        startScannerIfReady()
    }

    private func cancelAndDismiss() {
        viewModel.cancelMultiStageExchange()
        listener = nil
        switchToContacts?()
    }

    private func stopScanQualityTimer() {
        scanQualityTimer?.invalidate()
        scanQualityTimer = nil
    }

    /// Presentational scan-quality indicator — unrelated to the exchange
    /// clock. Stays a frontend timer per ADR-031 §Hardware: the camera
    /// pipeline is a platform concern.
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

    private func transferProgressText(received: UInt16, total: UInt16) -> String {
        if total > 0 {
            return "Receiving \(received)/\(total) chunks..."
        }
        return "Transferring data..."
    }

    // MARK: - Multi-Stage Scanner

    private func handleMultiStageScannedCode(_ code: String) {
        lastScanTimestamp = Date()
        // Core applies the scan to its state machine; subsequent state and
        // QR updates arrive via the listener callbacks.
        _ = viewModel.processMultiStageQr(raw: code)
    }

    // MARK: - Permission Needed State

    private var permissionNeededContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Camera Required")
                .font(Font.title3.weight(.semibold))

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
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
            .accessibilityIdentifier("exchange.grant_permission")
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
        let ecc: MobileQrEccLevel = switch correctionLevel.uppercased() {
        case "L": .low
        case "Q": .quartile
        case "H": .high
        default: .medium
        }
        // Gray foreground (#404040 ≈ 64) on light gray background (#E0E0E0 ≈ 224)
        // reduces screen glare at close face-to-face distance.
        guard let qr = try? generateQrBitmap(
            data: string, size: 512, ecc: ecc, dark: 64, light: 224, margin: 4
        ) else { return nil }
        let imageSize = Int(qr.size)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(qr.pixels) as CFData),
              let cgImage = CGImage(
                  width: imageSize, height: imageSize,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: imageSize,
                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }
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
