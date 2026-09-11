// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PresentationHostView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        GeometryReader { geometry in
            PresentationHostContent(
                state: viewModel.presentationState,
                useFrontCamera: viewModel.useFrontCamera,
                onCameraPermissionDenied: viewModel.sendCameraPermissionDenied,
                onEvent: { surfaceID, event in
                    viewModel.activateAndDispatch(surfaceID: surfaceID, event: event)
                },
                onDismissOverlay: viewModel.dismissPresentationOverlay
            )
            .onAppear {
                reportEnvironment(geometry.size)
            }
            .onChange(of: geometry.size) { size in
                reportEnvironment(size)
            }
            .onChange(of: reducedMotion) { _ in
                reportEnvironment(geometry.size)
            }
            .animation(
                reducedMotion ? nil : .easeOut(duration: 0.24),
                value: viewModel.presentationState.activeOverlay?.overlay.kind
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard let surfaceID = viewModel.presentationState.activeSurfaceID,
                              value.startLocation.x < 40,
                              value.translation.width > 60
                        else { return }
                        viewModel.activateAndDispatch(
                            surfaceID: surfaceID,
                            event: .backRequested(surfaceID: surfaceID)
                        )
                    },
                // The overlay is modal (`.isModal`), so an edge drag over it
                // must not reach the surface underneath: back-navigating a
                // surface the user cannot see leaves the menu drawn over a
                // destination they never chose — the defect class tracked in
                // 2026-08-07-ios-stale-overlay-and-raw-error-alert. `.subviews`
                // keeps the overlay's own gestures working.
                including: viewModel.presentationState.activeOverlay == nil ? .all : .subviews
            )
        }
        .alert(item: $viewModel.alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(alignment: .top) {
            if let message = viewModel.toastMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePickerSheet { data in
                viewModel.sendImageReceived(data: data)
            } onCancel: {
                viewModel.sendImagePickCancelled()
            }
        }
        .sheet(isPresented: $viewModel.showCameraPicker) {
            AVCameraCaptureSheet { data in
                viewModel.sendImageReceived(data: data)
            } onCancel: {
                viewModel.sendImagePickCancelled()
            }
        }
    }

    private func reportEnvironment(_ size: CGSize) {
        viewModel.dispatchPresentation(
            .environmentChanged(
                availableWidth: UInt32(max(0, size.width.rounded())),
                availableHeight: UInt32(max(0, size.height.rounded())),
                inputModes: [.touch],
                motion: reducedMotion ? .reduced : .full
            )
        )
    }
}
