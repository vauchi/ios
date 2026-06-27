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
    /// When `true`, the preview opens the front-facing wide-angle
    /// camera; when `false`, the back-facing one. Mirrors core's
    /// `Command::SwitchCamera { use_front }`. `QrCodeView` recreates
    /// the representable with `.id(useFrontCamera)` so a flip rebuilds
    /// the underlying `MultipartCameraView` rather than reconfiguring
    /// an in-flight `AVCaptureSession` (matches the Android
    /// `key(useFrontCamera)` recreate-on-flip strategy — cost is one
    /// session teardown per camera switch, well below camera-open
    /// latency).
    var useFrontCamera: Bool = false

    /// Forward a definitive camera-permission denial up to the view model
    /// (T0.5). Default no-op for the pre-bootstrap fallback path that has no
    /// AppViewModel.
    var onPermissionDenied: () -> Void = {}

    func makeUIView(context: Context) -> UIView {
        let view = MultipartCameraView(useFrontCamera: useFrontCamera)
        view.delegate = context.coordinator
        view.onPermissionDenied = onPermissionDenied
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

    /// Forwards a definitive camera-permission denial to core (T0.5). Guarded
    /// by `permissionDenialReported` so the `layoutSubviews`-driven
    /// `setupCamera` re-entry (captureSession stays nil on denial) can't fire it
    /// — or stack permission overlays — more than once.
    var onPermissionDenied: (() -> Void)?
    private var permissionDenialReported = false
    private let useFrontCamera: Bool

    init(useFrontCamera: Bool) {
        self.useFrontCamera = useFrontCamera
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used; views are constructed by MultipartCameraPreview")
    }

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
        switch CameraService.decision(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .proceed:
            initializeCamera()
        case .awaitCallback:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch CameraService.decision(forGranted: granted) {
                    case .proceed:
                        self.initializeCamera()
                    case .finish:
                        self.handlePermissionDenied()
                    case .awaitCallback:
                        break
                    }
                }
            }
        case .finish:
            handlePermissionDenied()
        }
    }

    /// Show the in-app overlay AND forward the denial to core exactly once
    /// (T0.5). The overlay is the local affordance; the forwarded event drives
    /// core's CameraGate so the exchange QR leg fails fast instead of waiting.
    private func handlePermissionDenied() {
        showPermissionDenied()
        guard !permissionDenialReported else { return }
        permissionDenialReported = true
        onPermissionDenied?()
    }

    private func initializeCamera() {
        let session = AVCaptureSession()
        // Configure the session inside a begin/commit block (Apple-
        // recommended pattern; matches `AVCameraCaptureSheet.swift`).
        // Outside the block, addInput/addOutput on a running session
        // is undefined behaviour, and on a fresh session it can race
        // with the recreate-on-flip teardown of the previous session
        // when the user toggles `useFrontCamera`.
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Pick the front- or back-facing wide-angle camera based on the
        // selector core last emitted (`Command::SwitchCamera`). Falls back
        // to the device-default video camera when the chosen position
        // isn't available — devices without a front camera are rare, but
        // the fallback prevents an empty preview if one ships.
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        let positionLabel = position == .front ? "front" : "back"
        let chosenDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        guard let device = chosenDevice ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            NSLog("[Vauchi] [QrCamera] Failed to acquire \(positionLabel) camera input")
            showCameraFailed(reason: "Failed to acquire \(positionLabel) camera")
            return
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            NSLog("[Vauchi] [QrCamera] Session cannot add \(positionLabel) camera input")
            showCameraFailed(reason: "Camera busy — try again")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }

        session.commitConfiguration()

        // The view's own backing layer is the preview layer (see
        // layerClass override), so just plug the session in. UIKit
        // auto-resizes the host layer with the view's bounds — no
        // manual frame management needed.
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        captureSession = session

        // AVCaptureSession surfaces *runtime* failures (camera released
        // by another process, device unplugged, etc.) only via this
        // notification — there is no return value, no callback. Without
        // the observer the session goes idle and the preview stays on
        // its last frame (or black if it never produced one).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            // Post-condition: `startRunning()` returns Void and does not
            // throw or signal failure. If the camera was held by the
            // previous session during the recreate-on-flip race (e.g.
            // the old `AVCaptureSession`'s `stopRunning()` in deinit
            // hadn't fully released the device yet), startRunning is a
            // no-op and the preview stays black with no diagnostic.
            // Surface that case explicitly — mirrors the post-condition
            // pattern used in the dt-* recipe sweep (2026-05-11).
            if !session.isRunning {
                NSLog("[Vauchi] [QrCamera] startRunning returned but session is not running (\(positionLabel))")
                DispatchQueue.main.async {
                    self?.showCameraFailed(reason: "Camera failed to start (busy?)")
                }
            }
        }
    }

    @objc private func handleRuntimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        NSLog("[Vauchi] [QrCamera] Runtime error code=\(error?.code ?? -1)")
        DispatchQueue.main.async { [weak self] in
            self?.showCameraFailed(reason: "Camera runtime error")
        }
    }

    private func showCameraFailed(reason: String) {
        let label = UILabel()
        label.text = "Camera unavailable\n\(reason)"
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
        NotificationCenter.default.removeObserver(self)
        captureSession?.stopRunning()
    }
}
