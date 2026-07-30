// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Native photo-library adapter used by generic Core platform effects.
struct ImagePickerSheet: UIViewControllerRepresentable {
    let onImageSelected: ([UInt8]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _: PHPickerViewController,
        context _: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImageSelected: onImageSelected,
            onCancel: onCancel
        )
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: ([UInt8]) -> Void
        let onCancel: () -> Void

        init(
            onImageSelected: @escaping ([UInt8]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onImageSelected = onImageSelected
            self.onCancel = onCancel
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(
                      UTType.image.identifier
                  )
            else {
                onCancel()
                return
            }

            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { [weak self] data, _ in
                guard let data else {
                    DispatchQueue.main.async {
                        self?.onCancel()
                    }
                    return
                }
                DispatchQueue.main.async {
                    self?.onImageSelected([UInt8](data))
                }
            }
        }
    }
}
