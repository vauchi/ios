// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenView.swift
// Generic wrapper that renders any core-driven screen via PlatformAppEngine.

import PhotosUI
import SwiftUI
import VauchiPlatform

/// Renders a core-driven screen by name using the shared `AppViewModel`.
///
/// Uses the shared `coreViewModel` from `VauchiViewModel` (injected via
/// `@EnvironmentObject`). All `CoreScreenView` instances share one
/// `PlatformAppEngine` — one DB connection, one engine cache.
///
/// When this view appears, it navigates the shared engine to `screenName`.
/// The engine's screen caching makes tab switches instant.
///
/// Usage:
/// ```swift
/// CoreScreenView(screenName: "Groups")
/// CoreScreenView(screenName: "Settings")
/// ```
struct CoreScreenView: View {
    let screenName: String
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var currentScreen: String?

    var body: some View {
        Group {
            if let coreVM = viewModel.coreViewModel,
               let screen = coreVM.currentScreen {
                ScreenRendererView(screen: screen, onAction: { action in
                    coreVM.handleAction(action)
                })
            } else {
                ProgressView("Loading...")
            }
        }
        .task(id: screenName) {
            navigateIfNeeded(to: screenName)
        }
        .alert(item: alertBinding) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: imagePickerBinding) {
            ImagePickerSheet { imageData in
                viewModel.coreViewModel?.sendImageReceived(data: imageData)
            } onCancel: {
                viewModel.coreViewModel?.sendImagePickCancelled()
            }
        }
        .sheet(isPresented: cameraPickerBinding) {
            CameraPickerSheet { imageData in
                viewModel.coreViewModel?.sendImageReceived(data: imageData)
            } onCancel: {
                viewModel.coreViewModel?.sendImagePickCancelled()
            }
        }
    }

    private func navigateIfNeeded(to screen: String) {
        guard currentScreen != screen else { return }
        currentScreen = screen
        viewModel.coreViewModel?.navigateTo(screenJson: "\"\(screen)\"")
    }

    private var alertBinding: Binding<AppViewModel.AlertMessage?> {
        Binding(
            get: { viewModel.coreViewModel?.alertMessage },
            set: { viewModel.coreViewModel?.alertMessage = $0 }
        )
    }

    private var imagePickerBinding: Binding<Bool> {
        Binding(
            get: { viewModel.coreViewModel?.showImagePicker ?? false },
            set: { viewModel.coreViewModel?.showImagePicker = $0 }
        )
    }

    private var cameraPickerBinding: Binding<Bool> {
        Binding(
            get: { viewModel.coreViewModel?.showCameraPicker ?? false },
            set: { viewModel.coreViewModel?.showCameraPicker = $0 }
        )
    }
}

// MARK: - Image Picker (PHPicker)

/// Wraps PHPickerViewController to select an image from the photo library.
struct ImagePickerSheet: UIViewControllerRepresentable {
    let onImageSelected: ([UInt8]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected, onCancel: onCancel)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: ([UInt8]) -> Void
        let onCancel: () -> Void

        init(onImageSelected: @escaping ([UInt8]) -> Void, onCancel: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onCancel()
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) else {
                    DispatchQueue.main.async { self?.onCancel() }
                    return
                }
                let bytes = Array(data)
                DispatchQueue.main.async { self?.onImageSelected(bytes) }
            }
        }
    }
}

// MARK: - Camera Picker

/// Wraps UIImagePickerController with camera source for capturing a photo.
struct CameraPickerSheet: UIViewControllerRepresentable {
    let onImageSelected: ([UInt8]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageSelected: ([UInt8]) -> Void
        let onCancel: () -> Void

        init(onImageSelected: @escaping ([UInt8]) -> Void, onCancel: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }
            let bytes = [UInt8](data)
            onImageSelected(bytes)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCancel()
        }
    }
}
