// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenView.swift
// Generic wrapper that renders any core-driven screen via PlatformAppEngine.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
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
/// CoreScreenView(actionId: "groups")      // tab body — opaque id from tabInfo()
/// CoreScreenView(screenName: "Settings")  // legacy sub-screen path
/// ```
struct CoreScreenView: View {
    /// What the shared engine navigates to when this view appears.
    ///
    /// `tab` forwards the opaque `action_id` from `tabInfo()` as
    /// `UserAction::NavigateToTab` — the zero-domain-vocab tab path
    /// (ADR-043 Am4). `screen` is the legacy serde-variant path still
    /// used by non-tab sub-screens (Settings, Sync, Backup, …) pending
    /// the `navigate_to_json` retirement tier.
    enum Target: Equatable {
        case tab(actionId: String)
        /// Render-only: render the engine's *current* screen, issue no
        /// navigation. Core has already navigated here.
        case current

        /// Stable key for `.task(id:)` so tab re-selection re-asserts.
        var taskId: String {
            switch self {
            case let .tab(actionId): "tab:\(actionId)"
            case .current: "current"
            }
        }
    }

    let target: Target
    @EnvironmentObject var viewModel: VauchiViewModel

    /// Tab body: navigate by the opaque canonical `action_id` from core.
    init(actionId: String) {
        target = .tab(actionId: actionId)
    }

    /// Render-only body: renders the shared engine's *current* screen
    /// without issuing any navigation. For native hardware wrappers
    /// (FaceToFace / NfcTap) that core has already navigated to — re-
    /// navigating would double-push `nav_history` (the android
    /// double-push bug, `2026-05-21-android-back-stack-and-bottom-nav-broken`).
    init(renderingCurrentScreen _: Void) {
        target = .current
    }

    var body: some View {
        // The actual rendering lives in `CoreScreenContent`, which observes
        // `coreViewModel` directly via `@ObservedObject`. The previous
        // pattern read `viewModel.coreViewModel?.currentScreen` from this
        // outer view, but `coreViewModel` is itself only `@Published` on
        // `viewModel` — SwiftUI re-renders when the `coreViewModel`
        // *reference* changes, not when its inner `@Published`
        // `currentScreen` does. After `navigate_to(...)` updated
        // `currentScreen`, the My Card body kept showing the previous
        // ScreenModel because nothing on `viewModel` had emitted, so the
        // outer view never recomposed. Splitting into an inner
        // `@ObservedObject coreVM` view fixes that — SwiftUI now subscribes
        // to `coreVM.objectWillChange` directly.
        Group {
            if let coreVM = viewModel.coreViewModel {
                CoreScreenContent(target: target, coreVM: coreVM)
            } else {
                ProgressView("Loading...")
            }
        }
    }
}

private struct CoreScreenContent: View {
    let target: CoreScreenView.Target
    @ObservedObject var coreVM: AppViewModel

    /// Drive the shared engine to this view's target. Tabs forward the
    /// opaque `action_id` (`NavigateToTab`); the render-only `.current`
    /// target issues no navigation (core has already navigated here).
    private func navigate() {
        switch target {
        case let .tab(actionId): coreVM.navigateToTab(actionId: actionId)
        case .current: break // render-only — core already navigated here
        }
    }

    var body: some View {
        Group {
            if let screen = coreVM.currentScreen {
                ScreenRendererView(screen: screen, onAction: { action in
                    coreVM.handleAction(action)
                })
            } else {
                ProgressView("Loading...")
            }
        }
        // All CoreScreenView instances share one engine — and therefore one
        // currentScreen. Whenever this view becomes visible (first mount or
        // MainTabView tab re-selection), re-assert this view's screen
        // because another tab may have driven the engine elsewhere since
        // we last ran (e.g. user pushed More → Settings, then tapped the
        // My Card tab — without re-asserting, HomeView would render the
        // Settings ScreenModel under its own header). Both .task and
        // .onAppear are kept: .task is async-aware and re-runs on id
        // change, .onAppear is the more reliable signal on TabView re-
        // selection. navigateTo to the active screen is cheap (engine
        // caches screens). Bug repro:
        // _private/docs/problems/2026-05-21-ios-shell-issues-from-walkthrough.
        .task(id: target.taskId) {
            navigate()
        }
        .onChange(of: coreVM.currentScreen?.screenId) { newId in
            syncQrFrameTimer(for: newId)
        }
        .onAppear {
            navigate()
            syncQrFrameTimer(for: coreVM.currentScreen?.screenId)
        }
        .onDisappear {
            coreVM.stopQrFrameTimer()
            coreVM.stopMultiStagePollTimer()
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
                coreVM.sendImageReceived(data: imageData)
            } onCancel: {
                coreVM.sendImagePickCancelled()
            }
        }
        .sheet(isPresented: cameraPickerBinding) {
            AVCameraCaptureSheet { imageData in
                coreVM.sendImageReceived(data: imageData)
            } onCancel: {
                coreVM.sendImagePickCancelled()
            }
        }
        // Note: the ADR-031 file-picker `.fileImporter` modifier was
        // hoisted out of CoreScreenView in `2026-05-04-ios-file-picker-
        // hoist`. The system document picker now hangs off ContentView
        // root + CoreOnboardingView so trigger paths from custom-view
        // tabs (MoreView) and from Onboarding `restore_backup` are
        // reachable; CoreScreenView no longer needs its own host.
    }

    /// Start the animated-QR timer while the ShowQr screen is visible; stop
    /// it everywhere else. Cheap to call unconditionally — both methods are
    /// idempotent.
    private func syncQrFrameTimer(for screenId: String?) {
        if screenId == "exchange_show_qr" {
            coreVM.startQrFrameTimer()
        } else {
            coreVM.stopQrFrameTimer()
        }
        // Multi-stage (Glance) exchange advances via a separate poll-driven
        // tick — its machine replaced the legacy `exchange_show_qr` engine
        // and is driven by `pollNotifications`, not `advanceQrFrameJson`
        // (Bug 5, `2026-05-30-exchange-screen-nav-visual-bugs`).
        if screenId == "multi_stage_exchange" {
            coreVM.startMultiStagePollTimer()
        } else {
            coreVM.stopMultiStagePollTimer()
        }
    }

    private var alertBinding: Binding<AppViewModel.AlertMessage?> {
        Binding(
            get: { coreVM.alertMessage },
            set: { coreVM.alertMessage = $0 }
        )
    }

    private var imagePickerBinding: Binding<Bool> {
        Binding(
            get: { coreVM.showImagePicker },
            set: { coreVM.showImagePicker = $0 }
        )
    }

    private var cameraPickerBinding: Binding<Bool> {
        Binding(
            get: { coreVM.showCameraPicker },
            set: { coreVM.showCameraPicker = $0 }
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
                  provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                onCancel()
                return
            }

            // Per ADR-042: hand raw bytes to core. Core converts/resizes to
            // WebP ≤ 32 KB internally — no frontend re-encode.
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else {
                    DispatchQueue.main.async { self?.onCancel() }
                    return
                }
                // swiftformat:disable:next spaceAroundBrackets spaceAroundParens
                let bytes = [UInt8](data)
                DispatchQueue.main.async { self?.onImageSelected(bytes) }
            }
        }
    }
}
