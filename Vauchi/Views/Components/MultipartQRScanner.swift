// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MultipartQRScanner.swift
// Scanner that captures multipart QR code frames and reassembles them.

import AVFoundation
import SwiftUI

// MARK: - Multipart Chunk Tracker

/// Tracks received multipart QR chunks and detects completion.
///
/// Parses chunk headers in the format `{index}/{total}/{crc32_hex}/{base64url_data}`
/// to track which parts have been received. Once all parts are collected, the
/// raw chunk strings are available for reassembly.
///
/// Note: Once `MobileMultipartDecoder` is published in `vauchi-mobile-swift`,
/// this tracker should be replaced with the Rust-backed decoder which also
/// performs CRC32 verification and base64url decoding. See Task 11.
final class MultipartChunkTracker: ObservableObject {
    @Published private(set) var receivedIndices: Set<Int> = []
    @Published private(set) var totalChunks: Int?
    @Published private(set) var isComplete = false
    @Published private(set) var lastError: String?

    /// Stored raw chunk strings keyed by index, for later reassembly.
    private var chunks: [Int: String] = [:]

    /// Add a scanned QR chunk string. Returns `true` if the chunk was new.
    func addChunk(_ chunk: String) -> Bool {
        // Parse header: {index}/{total}/{crc32_hex}/{data}
        let parts = chunk.split(separator: "/", maxSplits: 3)
        guard parts.count == 4,
              let index = Int(parts[0]),
              let total = Int(parts[1]),
              total > 0,
              index >= 0,
              index < total
        else {
            lastError = "Invalid chunk format"
            return false
        }

        // Validate consistent total across chunks
        if let existingTotal = totalChunks, existingTotal != total {
            lastError = "Inconsistent total: expected \(existingTotal), got \(total)"
            return false
        }

        totalChunks = total

        // Check for duplicate
        guard !receivedIndices.contains(index) else {
            return false
        }

        receivedIndices.insert(index)
        chunks[index] = chunk
        lastError = nil

        if receivedIndices.count == total {
            isComplete = true
        }

        return true
    }

    /// Returns the collected raw chunk strings in index order.
    ///
    /// Only valid when `isComplete` is `true`. These strings can be fed
    /// to `MobileMultipartDecoder` for CRC-verified reassembly once
    /// the bindings are available.
    func orderedChunks() -> [String] {
        guard let total = totalChunks, isComplete else { return [] }
        return (0 ..< total).compactMap { chunks[$0] }
    }

    /// Reset the tracker for a fresh scan session.
    func reset() {
        receivedIndices = []
        totalChunks = nil
        isComplete = false
        lastError = nil
        chunks = [:]
    }
}

// MARK: - MultipartQRScanner

/// Scanner that continuously captures QR codes and reassembles multipart payloads.
///
/// Uses AVFoundation camera capture to scan QR codes in real time. Each scanned frame
/// is parsed for its multipart header (index/total) to track progress. Once all chunks
/// have been received, the complete set of raw chunk strings is passed to the
/// `onComplete` callback for reassembly.
///
/// The actual CRC-verified reassembly into bytes will be handled by
/// `MobileMultipartDecoder` once the UniFFI bindings are published. See Task 11.
struct MultipartQRScanner: View {
    /// Called with the ordered raw chunk strings when all parts have been received.
    let onComplete: ([String]) -> Void

    /// Called when the user cancels the scanning flow.
    let onCancel: () -> Void

    @StateObject private var tracker = MultipartChunkTracker()
    @State private var latestChunk: String?

    var body: some View {
        VStack(spacing: 16) {
            // Camera scanner
            MultipartCameraPreview(onChunkScanned: handleChunkScanned)
                .ignoresSafeArea()
                .overlay(alignment: .center) {
                    scanFrameOverlay
                }

            // Status area
            VStack(spacing: 8) {
                if let error = tracker.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityLabel("Error: \(error)")
                }

                if let total = tracker.totalChunks {
                    VStack(spacing: 8) {
                        Text("Scanning: \(tracker.receivedIndices.count) / \(total) parts")
                            .font(.headline)
                            .accessibilityLabel(
                                "Received \(tracker.receivedIndices.count) of \(total) QR code parts"
                            )

                        ProgressView(
                            value: Double(tracker.receivedIndices.count),
                            total: Double(total)
                        )
                        .padding(.horizontal)
                        .accessibilityHidden(true) // Redundant with text label
                    }
                } else {
                    Text("Point camera at animated QR code")
                        .font(.headline)
                        .accessibilityLabel("Camera ready. Point at an animated QR code to begin scanning")
                }
            }
            .padding(.vertical, 8)

            Button("Cancel", role: .cancel, action: onCancel)
                .padding(.bottom)
                .accessibilityLabel("Cancel scanning")
                .accessibilityHint("Stops the multipart QR scanning process")
        }
    }

    // MARK: - Subviews

    private var scanFrameOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 3)
            .frame(width: 250, height: 250)
            .background(Color.clear)
            .accessibilityHidden(true)
    }

    // MARK: - Chunk Handling

    private func handleChunkScanned(_ chunk: String) {
        // Skip if we already processed this exact chunk string recently
        guard chunk != latestChunk else { return }
        latestChunk = chunk

        _ = tracker.addChunk(chunk)

        if tracker.isComplete {
            onComplete(tracker.orderedChunks())
        }
    }
}

// MARK: - Camera Preview for Continuous Scanning

/// Camera preview that continuously scans QR codes and reports each one via a callback.
///
/// Unlike the single-shot `CameraPreview` in `QRScannerView.swift`, this variant
/// reports every unique QR code it sees without debouncing duplicates across different
/// chunk payloads — enabling multipart QR reassembly.
struct MultipartCameraPreview: UIViewRepresentable {
    /// Called on the main thread each time a QR code is detected.
    let onChunkScanned: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = MultipartCameraView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onChunkScanned: onChunkScanned)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onChunkScanned: (String) -> Void
        private var lastScannedCode: String?
        private var lastScanTime: Date?

        init(onChunkScanned: @escaping (String) -> Void) {
            self.onChunkScanned = onChunkScanned
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = metadataObject.stringValue
            else {
                return
            }

            // Short debounce: skip if the exact same code was scanned within 100ms.
            // This prevents processing the same frame multiple times while still
            // allowing rapid cycling through different chunks (~333ms per chunk at 3fps).
            if let lastCode = lastScannedCode,
               let lastTime = lastScanTime,
               lastCode == code,
               Date().timeIntervalSince(lastTime) < 0.1 {
                return
            }

            lastScannedCode = code
            lastScanTime = Date()

            DispatchQueue.main.async {
                self.onChunkScanned(code)
            }
        }
    }
}

/// Camera view for continuous multipart QR scanning.
///
/// Mirrors the `CameraView` in `QRScannerView.swift` but is a separate class
/// to avoid coupling the single-shot scanner with the continuous multipart scanner.
class MultipartCameraView: UIView {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds

        if captureSession == nil {
            setupCamera()
        }
    }

    private func setupCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            initializeCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.initializeCamera()
                    }
                }
            }
        default:
            showPermissionDenied()
        }
    }

    private func initializeCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.addSublayer(preview)

        captureSession = session
        previewLayer = preview

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

// MARK: - Preview

#Preview {
    MultipartQRScanner(
        onComplete: { chunks in print("Complete: \(chunks.count) chunks") },
        onCancel: { print("Cancelled") }
    )
}
