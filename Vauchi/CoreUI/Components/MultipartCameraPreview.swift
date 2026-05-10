// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Continuous camera preview that streams every detected QR payload to a
// callback. Used by `QrCodeView` (scan mode) to feed `UserAction.textChanged`
// into core's exchange QR pipeline. Extracted from the now-retired
// `MultipartQRScanner.swift` (the wrapper view was orphan; this preview and
// its underlying UIView remain live).

import AVFoundation
import SwiftUI

struct MultipartCameraPreview: UIViewRepresentable {
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

            // Short debounce: drop the same payload within 100 ms so a single
            // visible frame is not delivered twice, while still allowing the
            // ~333 ms-per-chunk cadence used during multipart exchange.
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

final class MultipartCameraView: UIView {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    /// F2-NEW-3 follow-up: make the view's own backing layer the
    /// AVCaptureVideoPreviewLayer (Apple-recommended pattern; same shape
    /// as `AVCameraCaptureSheet.PreviewUIView`). The earlier addSublayer
    /// approach worked when the view filled the screen (legacy
    /// `Views/QRScannerView.swift` uses `.ignoresSafeArea()` with no
    /// SwiftUI clipShape) but failed under the new `QrCodeView` call
    /// site which pins the preview to 250×250 inside a
    /// `RoundedRectangle.clipShape`. SwiftUI's clipShape masks the host
    /// CALayer's contents — when the AVCaptureVideoPreviewLayer was a
    /// separate sublayer, the mask only applied to the empty host
    /// surface and the live camera frames rendered into a sibling layer
    /// that the mask did not cover, leaving the preview area black even
    /// though the AVCaptureSession was running and metadata callbacks
    /// fired. Hosting the preview as the view's primary layer puts the
    /// camera content directly under the SwiftUI mask, so clipShape now
    /// does what it claims.
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    // Safe: layerClass above guarantees the layer's runtime type.
    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    private var captureSession: AVCaptureSession?

    override func layoutSubviews() {
        super.layoutSubviews()

        // Defer setupCamera until SwiftUI hands us a non-zero size.
        // The first layoutSubviews still fires with bounds=zero under
        // `UIViewRepresentable` (no intrinsicContentSize); without
        // this guard, AVCaptureSession would start before the host
        // layer has valid dimensions and the metadata-output
        // coordinate space would be wrong.
        guard bounds.width > 0, bounds.height > 0 else { return }

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

        // The view's own backing layer is the preview layer (see
        // layerClass override), so just plug the session in. UIKit
        // auto-resizes the host layer with the view's bounds — no
        // manual frame management needed.
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        captureSession = session

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
