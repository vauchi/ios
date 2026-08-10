// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PresentationHostView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @FocusState private var focusedBindingID: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                surfaces
                    .padding(profileClass == .compact ? 0 : 16)
                    .safeAreaInset(edge: .bottom) {
                        commandBar
                            .padding(.horizontal, profileClass == .compact ? 8 : 20)
                            .padding(.bottom, 4)
                    }
                if let overlay = viewModel.presentationState.activeOverlay {
                    PresentationOverlayView(
                        overlay: overlay,
                        windowClass: profileClass,
                        reducedMotion: reducedMotion,
                        onAction: { event in
                            // Choosing an item closes the menu, and Core has
                            // to hear that: it clears its own open-overlay
                            // state only on `OverlayDismissed`, so staying
                            // quiet leaves its toggle rewriting the next
                            // request for this menu into a dismissal and the
                            // menu stops opening. Report it *before* the
                            // action, while this surface is still the active
                            // one — reporting it afterwards is rejected by
                            // Core's fail-closed validation and reaches the
                            // user as a "Presentation error" alert.
                            viewModel.dismissPresentationOverlay()
                            viewModel.activateAndDispatch(
                                surfaceID: overlay.surfaceID,
                                event: event
                            )
                        },
                        onDismiss: viewModel.dismissPresentationOverlay
                    )
                    .zIndex(20)
                }
            }
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

    private var profileClass: PresentationWindowClass {
        viewModel.presentationState.profile?.windowClass ?? .compact
    }

    @ViewBuilder
    private var surfaces: some View {
        let state = viewModel.presentationState
        let ids = state.visibleSurfaceIDs
        if state.profile?.paneLayout == .split {
            HStack(spacing: 16) {
                surfaceViews(ids)
            }
        } else {
            VStack {
                surfaceViews(ids)
            }
        }
    }

    private func surfaceViews(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { surfaceID in
            if let surface = viewModel.presentationState.surfaces[surfaceID] {
                PresentationSurfaceView(
                    surface: surface,
                    active: viewModel.presentationState.activeSurfaceID == surfaceID,
                    useFrontCamera: viewModel.useFrontCamera,
                    onCameraPermissionDenied: viewModel.sendCameraPermissionDenied,
                    focusedBinding: $focusedBindingID,
                    onEvent: { event in
                        viewModel.activateAndDispatch(
                            surfaceID: surfaceID,
                            event: event
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var commandBar: some View {
        if let surfaceID = viewModel.presentationState.activeSurfaceID {
            ContextCommandBarView(
                surfaceID: surfaceID,
                bar: viewModel.presentationState.activeBar,
                windowClass: profileClass,
                onEvent: { event in
                    viewModel.activateAndDispatch(
                        surfaceID: surfaceID,
                        event: event
                    )
                }
            )
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
