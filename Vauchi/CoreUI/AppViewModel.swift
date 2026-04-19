// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AppViewModel.swift
// Wraps PlatformAppEngine to drive ScreenRendererView for all core screens.
// Ported from macOS — same pattern, iOS-specific adaptations.

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

    let appEngine: PlatformAppEngine

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
            // Handled by native iOS flows
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
            default:
                // Other exchange commands handled by ExchangeCommandHandler
                break
            }
        }
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
