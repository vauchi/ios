// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AppViewModel.swift
// Wraps PlatformAppEngine to drive ScreenRendererView for all core screens.
// Ported from macOS — same pattern, iOS-specific adaptations.

import CoreUIModels
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import VauchiPlatform

@MainActor
class AppViewModel: ObservableObject {
    @Published var currentScreen: ScreenModel?
    @Published var validationErrors: [String: String] = [:]
    @Published var alertMessage: AlertMessage?
    @Published var toastMessage: String?
    @Published var toastUndoActionId: String?
    @Published var availableScreens: [String] = []
    @Published var selectedScreen: String?
    @Published var showImagePicker = false
    @Published var showCameraPicker = false
    /// Set when core emits `ExchangeCommand::FilePickFromUser`. The
    /// view layer presents a `.fileImporter` keyed on this state; on
    /// pick / cancel it calls back into `sendFilePicked` /
    /// `sendFilePickCancelled` which unset the state and forward the
    /// matching `ExchangeHardwareEvent`. Phase 3 of
    /// `2026-05-03-core-file-picker-command`.
    @Published var pendingFilePick: PendingFilePick?

    struct PendingFilePick: Identifiable {
        let purpose: FilePickPurpose
        let acceptedMimeTypes: [String]
        var id: String {
            String(describing: purpose)
        }
    }

    let appEngine: PlatformAppEngine

    /// Phase 2A (core-gui-architecture-alignment): listener registered with
    /// `PlatformAppEngine.setEventListener`. Core invokes
    /// `onScreensInvalidated` off-thread on background sync, delivery
    /// receipts, device-link completion, etc. Kept as a property so the
    /// UniFFI callback interface's lifetime is bound to the view model.
    private var eventListener: InvalidationListener?

    /// Timer that drives animated-QR frame advancement (~10fps) while the
    /// "Share Your Code" screen is visible. See `startQrFrameTimer` /
    /// `stopQrFrameTimer`; the view layer toggles it via `onChange` of
    /// `currentScreen?.screenId`.
    private var qrFrameTimer: Timer?

    /// Count of consecutive decode failures. When the count hits
    /// `maxConsecutiveQrDecodeFailures` the timer self-stops to avoid
    /// infinite retry on a persistent decode mismatch (e.g. core
    /// ScreenModel format drift); the frozen QR is itself the user signal.
    private var qrFrameDecodeFailures = 0
    private static let maxConsecutiveQrDecodeFailures = 10 // ~1s at 10 fps

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(appEngine: PlatformAppEngine) {
        self.appEngine = appEngine
        loadAvailableScreens()
        loadScreen()
        attachEventListener()
    }

    private func attachEventListener() {
        let listener = InvalidationListener { [weak self] screenIds in
            // Core calls this on whatever thread it dispatched the event
            // on (often the thread that handled a user action). The
            // UniFFI Mutex guarding `PlatformAppEngine` will deadlock if
            // we touch the engine on the same stack — hop to main first.
            DispatchQueue.main.async {
                guard let self else { return }
                for id in screenIds {
                    let quoted = "\"\(id)\""
                    _ = try? self.appEngine.invalidateScreenJson(screenJson: quoted)
                }
                self.loadScreen()
            }
        }
        do {
            try appEngine.setEventListener(listener: listener)
            eventListener = listener
        } catch {
            #if DEBUG
                print("AppViewModel: failed to attach event listener: \(error)")
            #endif
        }
    }

    /// Test-only accessors for `PlatformEventListenerTests`.
    var hasEventListener: Bool {
        eventListener != nil
    }

    var eventListenerForTesting: PlatformEventListener? {
        eventListener
    }

    // MARK: - Screen Loading

    func loadAvailableScreens() {
        do {
            let json = try appEngine.availableScreensJson()
            guard let data = json.data(using: .utf8) else { return }
            availableScreens = try JSONDecoder().decode([String].self, from: data)
        } catch {
            #if DEBUG
                print("AppViewModel: failed to load available screens: \(error)")
            #endif
        }
    }

    func loadScreen() {
        do {
            let json = try appEngine.currentScreenJson()
            guard let data = json.data(using: .utf8) else { return }
            currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
            validationErrors = [:]
            updateSelectedScreen()
        } catch {
            #if DEBUG
                print("AppViewModel: failed to load screen: \(error)")
            #endif
        }
    }

    // MARK: - Action Handling

    func handleAction(_ action: UserAction) {
        do {
            let actionData = try coreJSONEncoder.encode(action)
            guard let actionJson = String(data: actionData, encoding: .utf8) else { return }
            let resultJson = try appEngine.handleActionJson(actionJson: actionJson)
            guard let resultData = resultJson.data(using: .utf8) else { return }
            let result = try coreJSONDecoder.decode(ActionResult.self, from: resultData)
            applyResult(result)
        } catch {
            #if DEBUG
                print("AppViewModel: failed to handle action: \(error)")
            #endif
        }
    }

    // MARK: - Navigation

    func navigateTo(screenJson: String) {
        do {
            let json = try appEngine.navigateToJson(screenJson: screenJson)
            guard let data = json.data(using: .utf8) else { return }
            currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
            validationErrors = [:]
            loadAvailableScreens()
            updateSelectedScreen()
        } catch {
            #if DEBUG
                print("AppViewModel: failed to navigate: \(error)")
            #endif
        }
    }

    /// Dispatch an incoming `vauchi://exchange?...` deep link URI to core.
    ///
    /// On success core navigates to `AppScreen::DeepLinkConsent` and
    /// `currentScreen` updates to the consent ScreenModel — the native
    /// alert is shown by `VauchiApp` while that screen is current.
    /// Throws on parse failure (UniFFI `MobileError::InvalidInput`); the
    /// caller surfaces the message via the existing error alert path.
    func handleDeepLinkUri(_ uri: String) throws {
        let json = try appEngine.handleDeepLinkUri(uri: uri)
        guard let data = json.data(using: .utf8) else {
            throw NSError(
                domain: "AppViewModel",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid screen JSON"]
            )
        }
        currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
        validationErrors = [:]
        loadAvailableScreens()
        updateSelectedScreen()
    }

    func navigateBack() {
        do {
            let json = try appEngine.navigateBackJson()
            guard let data = json.data(using: .utf8) else { return }
            currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
            validationErrors = [:]
        } catch {
            #if DEBUG
                print("AppViewModel: failed to navigate back: \(error)")
            #endif
        }
    }

    func invalidateAll() {
        do {
            try appEngine.invalidateAll()
            loadAvailableScreens()
            loadScreen()
        } catch {
            #if DEBUG
                print("AppViewModel: failed to invalidate: \(error)")
            #endif
        }
    }

    // MARK: - Animated QR Frame Cycling

    // NOTE: this block is duplicated in vauchi/macos at
    // `Vauchi/ViewModels/AppViewModel.swift`. Keep the two in sync until the
    // shared-module decision lands — see `_private/docs/problems/\
    // 2026-04-19-qr-frame-timer-ios-macos-duplication/`.

    /// Start a 10 fps timer that advances animated-QR frames on the ShowQr screen.
    ///
    /// Idempotent: calling while already running is a no-op. The view calls
    /// this on `.onAppear` / when `screenId` becomes `exchange_show_qr`.
    func startQrFrameTimer() {
        guard qrFrameTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceQrFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        qrFrameTimer = timer
    }

    /// Stop the animated-QR timer if running. The view calls this on
    /// `.onDisappear` / when `screenId` leaves `exchange_show_qr`.
    func stopQrFrameTimer() {
        qrFrameTimer?.invalidate()
        qrFrameTimer = nil
    }

    /// Test-only accessor — true while the QR frame timer is active.
    /// Exposed at `internal` visibility so `@testable` imports can assert
    /// idempotent start/stop without reaching into the private Timer.
    var hasActiveQrFrameTimer: Bool {
        qrFrameTimer != nil
    }

    private func advanceQrFrame() {
        do {
            guard let frameJson = try appEngine.advanceQrFrameJson() else {
                qrFrameDecodeFailures = 0
                return
            }
            guard let data = frameJson.data(using: .utf8) else {
                recordQrFrameFailure()
                return
            }
            let frame = try coreJSONDecoder.decode(ScreenModel.self, from: data)
            currentScreen = frame
            qrFrameDecodeFailures = 0
        } catch {
            #if DEBUG
                print("AppViewModel: failed to advance QR frame: \(error)")
            #endif
            recordQrFrameFailure()
        }
    }

    /// Record a decode failure and stop the timer once the consecutive-
    /// failure threshold is crossed. Prevents runaway retries when core's
    /// ScreenModel format drifts; the frozen QR is itself the visible signal.
    private func recordQrFrameFailure() {
        qrFrameDecodeFailures += 1
        if qrFrameDecodeFailures >= Self.maxConsecutiveQrDecodeFailures {
            stopQrFrameTimer()
            qrFrameDecodeFailures = 0
        }
    }

    // MARK: - Toast

    func showToast(_ message: String, undoActionId: String? = nil, durationMs: UInt32 = 3000) {
        withAnimation {
            toastMessage = message
            toastUndoActionId = undoActionId
        }
        let duration = max(Double(durationMs) / 1000.0, 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, toastMessage == message else { return }
            withAnimation {
                self.toastMessage = nil
                self.toastUndoActionId = nil
            }
        }
    }

    // MARK: - Private

    private static let screenIdPrefixToTab: [(prefix: String, tab: String)] = [
        ("my_info", "MyInfo"),
        ("contact", "Contacts"),
        ("exchange", "Exchange"),
        ("groups", "Groups"),
        ("group_detail", "Groups"),
        ("device_replacement", "More"),
        ("more", "More"),
    ]

    private func updateSelectedScreen() {
        guard let screenId = currentScreen?.screenId else { return }
        for mapping in Self.screenIdPrefixToTab where screenId.hasPrefix(mapping.prefix) {
            selectedScreen = mapping.tab
            return
        }
    }

    private func navigateToScreen(_ screenObject: [String: Any]) {
        do {
            let payload = try JSONSerialization.data(withJSONObject: screenObject)
            if let screenJson = String(data: payload, encoding: .utf8) {
                navigateTo(screenJson: screenJson)
            }
        } catch {
            #if DEBUG
                print("AppViewModel: failed to encode screen navigation: \(error)")
            #endif
        }
    }

    private func applyResult(_ result: ActionResult) {
        switch result {
        case let .updateScreen(screen):
            currentScreen = screen
            validationErrors = [:]
        case let .navigateTo(screen):
            currentScreen = screen
            validationErrors = [:]
        case let .validationError(componentId, message):
            validationErrors[componentId] = message
        case .complete, .wipeComplete:
            loadScreen()
        case .completeWith:
            // CompleteWith is consumed by AppEngine.route_result in core,
            // which re-emits NavigateTo to the destination screen — frontends
            // never observe it during normal post-onboarding routing.
            break
        case let .openUrl(url):
            if let nsUrl = URL(string: url) {
                UIApplication.shared.open(nsUrl)
            }
        case let .showAlert(title, message):
            alertMessage = AlertMessage(title: title, message: message)
        case let .openContact(contactId):
            navigateToScreen(["ContactDetail": ["contact_id": contactId]])
        case let .editContact(contactId):
            navigateToScreen(["ContactEdit": ["contact_id": contactId]])
        case let .openEntryDetail(fieldId):
            navigateToScreen(["EntryDetail": ["field_id": fieldId]])
        case let .showToast(message, undoActionId):
            // Reload screen — core may have navigated internally
            // (e.g. archive_contact intercept calls navigate_back()
            // before returning ShowToast).
            loadScreen()
            showToast(message, undoActionId: undoActionId)
        case .requestCamera:
            loadScreen()
        case .startDeviceLink, .startBackupImport:
            // `.startDeviceLink` is handled by native iOS flows.
            // `.startBackupImport` is retired — core no longer emits it
            // (Phase 2B routes backup restore through the file-picker
            // command/event path); kept here so the switch stays
            // exhaustive against the still-present enum variant.
            break
        case let .exchangeCommands(commands):
            handleExchangeCommands(commands)
        case .showFormDialog:
            // Dialog presentation handled by NavigateTo — no separate action needed
            break
        case .previewAs:
            // Card preview handled by NavigateTo — no separate action needed
            break
        case .unknown:
            break
        }
    }

    // MARK: - Exchange Command Handling

    private func handleExchangeCommands(_ commands: [ExchangeCommandDTO]) {
        for command in commands {
            switch command {
            case .imagePickFromLibrary:
                showImagePicker = true
            case .imageCaptureFromCamera:
                showCameraPicker = true
            case .imagePickFromFile:
                // iOS uses photo library instead of file picker for images
                sendImagePickCancelled()
            case let .filePickFromUser(acceptedMimeTypes, purpose):
                // Phase 3 of 2026-05-03-core-file-picker-command. Stash
                // the parameters so the view layer can present a
                // `.fileImporter`. Selection / cancel route back via
                // `sendFilePicked` / `sendFilePickCancelled`.
                pendingFilePick = PendingFilePick(
                    purpose: purpose,
                    acceptedMimeTypes: acceptedMimeTypes
                )
            default:
                // Other exchange commands handled by ExchangeCommandHandler
                break
            }
        }
    }

    /// Send picked file bytes back to core. Called from the view layer's
    /// `.fileImporter(onCompletion:)` after the user selects a file.
    /// Always clears `pendingFilePick` so the modal dismisses even if
    /// core's response triggers a re-render.
    func sendFilePicked(bytes: [UInt8], filename: String) {
        pendingFilePick = nil
        sendHardwareEvent(.filePickedFromUser(bytes: Data(bytes), filename: filename))
    }

    /// Notify core that the user cancelled the file picker. Same
    /// dismissal semantics as `sendFilePicked`.
    func sendFilePickCancelled() {
        pendingFilePick = nil
        sendHardwareEvent(.filePickCancelledByUser)
    }

    /// Send selected image bytes back to core as an ImageReceived hardware event.
    func sendImageReceived(data: [UInt8]) {
        sendHardwareEvent(.imageReceived(data: Data(data)))
    }

    /// Notify core that the user cancelled image picking.
    func sendImagePickCancelled() {
        sendHardwareEvent(.imagePickCancelled)
    }

    private func sendHardwareEvent(_ event: MobileExchangeHardwareEvent) {
        do {
            if let resultJson = try appEngine.handleHardwareEvent(event: event) {
                guard let resultData = resultJson.data(using: .utf8) else { return }
                let result = try coreJSONDecoder.decode(ActionResult.self, from: resultData)
                applyResult(result)
            }
        } catch {
            #if DEBUG
                print("AppViewModel: failed to send hardware event: \(error)")
            #endif
        }
    }
}

/// UniFFI callback target for core screen invalidations. Declared as a
/// `final class` (not a struct) because the binding protocol requires
/// `AnyObject`. The view model owns the instance so the FFI-held
/// reference stays alive as long as the engine is in use.
private final class InvalidationListener: PlatformEventListener {
    private let handler: ([String]) -> Void

    init(handler: @escaping ([String]) -> Void) {
        self.handler = handler
    }

    func onScreensInvalidated(screenIds: [String]) {
        handler(screenIds)
    }
}
