// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AVCameraCaptureSheet.swift
// Camera capture using AVCaptureSession + AVCapturePhotoOutput so we can
// hand raw HEIC/JPEG bytes from `AVCapturePhoto.fileDataRepresentation()`
// straight to core. Replaces the prior `UIImagePickerController` wrapper,
// which only exposed a decoded `UIImage` and forced a frontend re-encode
// (ADR-042: frontends pass raw bytes; core owns the WebP pipeline).

import AVFoundation
import SwiftUI
import UIKit

struct AVCameraCaptureSheet: View {
    let onImageSelected: ([UInt8]) -> Void
    let onCancel: () -> Void

    @StateObject private var coordinator = CaptureCoordinator()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: coordinator.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.white)
                        .padding()
                    Spacer()
                }

                Spacer()

                Button { coordinator.capturePhoto() } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 4).frame(width: 80, height: 80))
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            coordinator.onPhotoCaptured = { data in onImageSelected([UInt8](data)) }
            coordinator.onUnavailable = { onCancel() }
            coordinator.start()
        }
        .onDisappear { coordinator.stop() }
    }
}

private final class CaptureCoordinator: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "vauchi.camera-capture")

    var onPhotoCaptured: ((Data) -> Void)?
    var onUnavailable: (() -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    configureAndStart()
                } else {
                    DispatchQueue.main.async { self.onUnavailable?() }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.onUnavailable?() }
        @unknown default:
            DispatchQueue.main.async { self.onUnavailable?() }
        }
    }

    func capturePhoto() {
        queue.async { [weak self] in
            guard let self, session.isRunning else { return }
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }

            session.beginConfiguration()
            session.sessionPreset = .photo

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)

            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input),
                  session.canAddOutput(self.output)
            else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.onUnavailable?() }
                return
            }

            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.onUnavailable?() }
            return
        }
        DispatchQueue.main.async { self.onPhotoCaptured?(data) }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_: PreviewUIView, context _: Context) {}

    final class PreviewUIView: UIView {
        // swiftlint:disable:next static_over_final_class
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        // Safe: layerClass above guarantees the layer's runtime type.
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
