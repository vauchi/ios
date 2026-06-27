// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

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
    @Published var showImagePicker = false
    @Published var showCameraPicker = false
    /// Set when core emits `ExchangeCommand::FilePickFromUser`. The
    /// view layer presents a `.fileImporter` keyed on this state; on
    /// pick / cancel it calls back into `sendFilePicked` /
    /// `sendFilePickCancelled` which unset the state and forward the
    /// matching `ExchangeHardwareEvent`. Phase 3 of
    /// `2026-05-03-core-file-picker-command`.
    @Published var pendingFilePick: PendingFilePick?

    /// Active camera selector for `Component::QrCode` scan mode.
    /// Flips when core's `MultiStageExchangeEngine` emits
    /// `Command::SwitchCamera { use_front }` in response to the
    /// `switch_camera` action. `QrCodeView.qrScannerView` reads this
    /// via `@EnvironmentObject` and uses `.id(useFrontCamera)` so
    /// SwiftUI recreates `MultipartCameraPreview` on flip, mirroring
    /// the Android `key(useFrontCamera)` recreate-on-flip pattern.
    /// Default `false` (back camera), matching `AVCaptureDevice
    /// .default(for: .video)` semantics on every supported device.
    @Published var useFrontCamera: Bool = false

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

    /// Timer that drives the multi-stage (Glance) exchange machine (~5fps)
    /// while the `multi_stage_exchange` screen is visible. Post slice-32m
    /// the core cycle thread is gone; the machine advances only when the
    /// frontend calls `pollNotifications`, which also fires
    /// `onScreensInvalidated` (→ `loadScreen`). Without this tick the
    /// own-QR never appears (Bug 5,
    /// `2026-05-30-exchange-screen-nav-visual-bugs`). The view toggles it
    /// via `onChange` of `currentScreen?.screenId`. Distinct from
    /// `qrFrameTimer`, which drives the legacy `exchange_show_qr` path via
    /// `advanceQrFrameJson` (gated to `AppScreen::Exchange` in core).
    private var multiStagePollTimer: Timer?
    private var corePollTimer: Timer?

    /// NFC reader-mode hardware bridge for the TapTap exchange
    /// (`NfcActivate`/`NfcSendApdu`/`NfcDeactivate` commands). Held as
    /// the `NFCExchangeDispatching` protocol so tests can inject a spy
    /// instead of opening a real `NFCTagReaderSession`; production uses
    /// the CoreNFC-backed `NFCExchangeService`. `lazy` so the session
    /// host is built only when the first NFC command arrives.
    lazy var nfcService: NFCExchangeDispatching = NFCExchangeService()

    /// CoreBluetooth bridge for engine-driven BLE exchange commands
    /// (`BleStartAdvertising`/`BleStartScanning`/`BleConnect`/… commands).
    /// `lazy` so the central/peripheral managers are built only when the
    /// first BLE command arrives; `activateBleIfNeeded` installs the
    /// hardware-event callback exactly once.
    lazy var bleService = BleExchangeService()
    private var bleActivated = false

    /// Install the `MobileEvent` callback on `bleService` the first time a
    /// BLE command is dispatched. Mirrors the NFC `activate(payload:)`
    /// wiring: the closure forwards every event the service emits
    /// (`bleDeviceDiscovered`, `bleConnected`, `bleCharacteristicNotified`,
    /// hardware errors) back into core via `sendHardwareEvent`.
    private func activateBleIfNeeded() {
        guard !bleActivated else { return }
        bleActivated = true
        bleService.activate { [weak self] event in
            self?.sendHardwareEvent(event)
        }
    }

    /// One-shot location capture for the exchange "where we met" annotation
    /// (ADR-051). Driven by `Command::LocationRequest` in `handleExchangeCommands`.
    lazy var locationService = LocationService()

    /// True while a `LocationRequest` capture is in flight. Lets tests assert
    /// the command started a capture without touching the OS modal (CC-23).
    @Published var locationRequestInFlight = false

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(appEngine: PlatformAppEngine) {
        self.appEngine = appEngine
        loadScreen()
        attachEventListener()
        startCorePollTimer()
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

    func loadScreen() {
        do {
            let json = try appEngine.currentScreenJson()
            guard let data = json.data(using: .utf8) else { return }
            currentScreen = try coreJSONDecoder.decode(ScreenModel.self, from: data)
            validationErrors = [:]
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
            // Phase 2b: handleActionJson now returns
            // `{"action_result": <ActionResult>, "commands": [<CommandDTO>]}`.
            // The lifecycle commands carry brightness / idle-timer requests
            // emitted by `WorkflowEngine::screen_entered/screen_exited`.
            let envelope = try coreJSONDecoder.decode(ActionResultEnvelope.self, from: resultData)
            applyResult(envelope.actionResult)
            if !envelope.commands.isEmpty {
                handleExchangeCommands(envelope.commands)
            }
        } catch {
            #if DEBUG
                print("AppViewModel: failed to handle action: \(error)")
            #endif
        }
    }

    // MARK: - Navigation

    // `navigateTo(screenJson:)` (the `appEngine.navigateToJson` wrapper) was
    // retired in S3 of `2026-06-02-ios-exchange-flow-core-driven` — every iOS
    // screen now reaches core via the typed `navigateToTab` / `handleAction`
    // paths or renders the engine's current screen render-only. The core
    // `navigate_to_json` UniFFI surface is deleted in S5 (core MR) once iOS
    // ships caller-free.

    /// The bottom-bar tabs, sourced from core's `nav_items(.mobile)`
    /// (ADR-043 Am4; ADR-023 Am1). Each carries an opaque `actionId`
    /// (forward via `navigateToTab`), a core-resolved `label`, and an SF
    /// Symbol `icon` — replacing the hardcoded `MainTabView` domain
    /// literals so iOS stays a pure renderer. Returns `[]` only if the
    /// engine call throws (logged in DEBUG); the bar then renders empty
    /// rather than crashing.
    func tabs() -> [MobileTabInfo] {
        do {
            return try appEngine.navItems(layout: .mobile, locale: LocalizationService.shared.currentLocale)
        } catch {
            #if DEBUG
                print("AppViewModel: failed to load tabs: \(error)")
            #endif
            return []
        }
    }

    /// Forward a tab tap as `UserAction::NavigateToTab { action_id }`.
    ///
    /// `actionId` is the opaque canonical id handed out by `tabs()` (e.g.
    /// "groups"); core resolves it to the canonical screen and returns
    /// `NavigateTo`. The frontend never parses or constructs the domain
    /// variant — that is the zero-domain-vocab Tier-1 contract (ADR-043
    /// Am4 / tier0-d plan item 2).
    ///
    /// Dispatched through the typed `handleAction(_:)` path (encode →
    /// `handleActionJson` → apply result + lifecycle commands), then
    /// refreshes the available-screens list. Requires the
    /// `UserAction.navigateToTab` case from vauchi-platform-swift (added
    /// in vauchi-platform-swift!59); does not compile against bindings
    /// without it.
    func navigateToTab(actionId: String) {
        handleAction(.navigateToTab(actionId: actionId))
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
    }

    /// Whether the current screen offers a back step, per the engine's
    /// nav state (`AppScreen` history + in-engine sub-flow back). Drives
    /// the core-driven back chrome the shell renders above sub-screens,
    /// so the frontend no longer depends on a footer "Back" action.
    func canGoBack() -> Bool {
        (try? appEngine.canGoBack()) ?? false
    }

    func navigateBack() {
        do {
            let json = try appEngine.navigateBackJson()
            guard let data = json.data(using: .utf8) else { return }
            // Phase 2b envelope shape (see `navigateTo`).
            let envelope = try coreJSONDecoder.decode(ScreenEnvelope.self, from: data)
            currentScreen = envelope.screen
            validationErrors = [:]
            if !envelope.commands.isEmpty {
                handleExchangeCommands(envelope.commands)
            }
        } catch {
            #if DEBUG
                print("AppViewModel: failed to navigate back: \(error)")
            #endif
        }
    }

    func invalidateAll() {
        do {
            try appEngine.invalidateAll()
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

    // MARK: - Multi-Stage Exchange Polling (Bug 5)

    /// Start a ~5fps timer that drives the multi-stage exchange machine by
    /// polling core. Each tick runs `advance_multi_stage_session` inside the
    /// engine and fires `onScreensInvalidated`; the invalidation listener
    /// refetches the screen so the cycling own-QR + protocol progress
    /// surface. Idempotent. The view calls this when `screenId` becomes
    /// `multi_stage_exchange` and stops it on exit. See `multiStagePollTimer`.
    func startMultiStagePollTimer() {
        guard multiStagePollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Side effect is the point — the returned notifications are
            // drained by the global poll; matches Android's
            // `tickMultiStageExchange`.
            _ = try? appEngine.pollNotifications()
        }
        RunLoop.main.add(timer, forMode: .common)
        multiStagePollTimer = timer
    }

    /// Stop the multi-stage poll timer if running. The view calls this on
    /// `.onDisappear` / when `screenId` leaves `multi_stage_exchange`.
    func stopMultiStagePollTimer() {
        multiStagePollTimer?.invalidate()
        multiStagePollTimer = nil
    }

    /// Test-only accessor — true while the multi-stage poll timer is active.
    var hasActiveMultiStagePollTimer: Bool {
        multiStagePollTimer != nil
    }

    // MARK: - Core Cadence Poll (bounded-wait exchange timeout)

    /// Tick the engine on a ~1s app-level cadence so bounded-wait exchanges
    /// (BLE / NFC / cable discovery) fail at their stall budget instead of
    /// "Searching…" forever. `pollNotifications` advances the active engine and
    /// fires `onScreensInvalidated`; the listener refetches, surfacing
    /// `exchange_failed` once `BLE_STEP_TIMEOUT_SECS` (60s) elapses. The 30s
    /// notification timer also ticks the engine, but too coarsely to fire the
    /// deadline on time — this is the iOS counterpart of the Android
    /// `MainActivity` pump (`CORE_CADENCE_TICK_INTERVAL_MS`). Started in `init`
    /// and runs on every core screen; the closure self-invalidates on dealloc
    /// because no view manages its lifecycle (unlike the multi-stage sibling).
    /// Idempotent.
    func startCorePollTimer() {
        guard corePollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            _ = try? appEngine.pollNotifications()
        }
        RunLoop.main.add(timer, forMode: .common)
        corePollTimer = timer
    }

    func stopCorePollTimer() {
        corePollTimer?.invalidate()
        corePollTimer = nil
    }

    /// Test-only accessor — true while the app-level core pump is active.
    var hasActiveCorePollTimer: Bool {
        corePollTimer != nil
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

    /// Internal (not private) so tests can pin the ActionResult →
    /// @Published contract directly, same seam as handleExchangeCommands.
    func applyResult(_ result: ActionResult) {
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
        case .completeWith, .openContact, .editContact, .openEntryDetail:
            // Resolved to NavigateTo by AppEngine.route_result in core —
            // frontends never observe these raw (ADR-043 Am4). CompleteWith
            // re-emits the post-onboarding destination; OpenContact /
            // EditContact / OpenEntryDetail re-emit the contact / edit /
            // entry screens.
            break
        case let .openUrl(url):
            if let nsUrl = URL(string: url) {
                UIApplication.shared.open(nsUrl)
            }
        case let .showAlert(title, message):
            alertMessage = AlertMessage(title: title, message: message)
        case let .showToast(message, undoActionId):
            // Reload screen — core may have navigated internally
            // (e.g. archive_contact intercept calls navigate_back()
            // before returning ShowToast).
            loadScreen()
            showToast(message, undoActionId: undoActionId)
        case .requestCamera:
            loadScreen()
        case .startDeviceLink:
            // Handled by native iOS flows.
            break
        case let .commands(commands):
            handleExchangeCommands(commands)
        case .showFormDialog:
            // Dialog presentation handled by NavigateTo — no separate action needed
            break
        case .previewAs:
            // Card preview handled by NavigateTo — no separate action needed
            break
        case .biometricUnlockOutcome:
            // Consumed by VauchiViewModel.authenticateAndRetry(), which
            // reports the biometric hardware event and decodes the outcome
            // directly to drive appState — it never flows through here.
            break
        case .unknown:
            break
        }
    }

    // MARK: - Exchange Command Handling

    /// Snapshot of the platform brightness captured on the first
    /// non-`nil` `setScreenBrightness` command, restored on the
    /// subsequent `nil`. Defensive against `nil` arriving without a
    /// preceding `Some` (no-op then).
    private var savedBrightness: CGFloat?

    /// Dispatch one or more core-emitted `Command`s. Called from
    /// `applyResult` for `ActionResult.commands` and from the Phase 2b
    /// envelope-drain path in `handleAction` / `navigateTo` /
    /// `navigateBack`. Slice 32c retired `OnboardingViewModel`; the
    /// Onboarding flow now drives this same `AppViewModel`, so the
    /// envelope-drain path covers Onboarding commands too (no separate
    /// `OnboardingViewModel.onExchangeCommands` bridge any more).
    func handleExchangeCommands(_ commands: [CommandDTO]) {
        for command in commands {
            // BLE + audio commands are dispatched in their own helpers to
            // keep this switch within SwiftLint's complexity budget.
            if handleTransportCommand(command) { continue }
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
            case let .setScreenBrightness(level):
                // Phase 2b screen-presentation lifecycle command. Mirrors
                // `MultiStageExchangeEngine::screen_entered/screen_exited`
                // in core: `Some(level)` snapshots the prior brightness
                // (so a subsequent `nil` restores it), `nil` restores.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let level {
                        if savedBrightness == nil {
                            savedBrightness = UIScreen.main.brightness
                        }
                        UIScreen.main.brightness = max(0.0, min(1.0, CGFloat(level)))
                    } else if let prior = savedBrightness {
                        UIScreen.main.brightness = prior
                        savedBrightness = nil
                    }
                }
            case let .setIdleTimerDisabled(disabled):
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = disabled
                }
            case let .setOrientationLock(orientation):
                // Phase 2c lifecycle command: bridge to the SwiftUI
                // orientation gate consulted by `AppDelegate
                // .application(_:supportedInterfaceOrientationsFor:)`.
                // `nil` clears the lock (returns to portrait+landscape);
                // `.portrait` / `.landscape` clamps to that mask. The
                // gate lives in `OrientationLock` (App layer).
                DispatchQueue.main.async {
                    OrientationLock.shared.setMask(orientation?.uiKitMask)
                }
            case let .switchCamera(useFront):
                // Camera-selector toggle from
                // `MultiStageExchangeEngine`'s `switch_camera` action.
                // `QrCodeView.qrScannerView` observes [useFrontCamera]
                // and uses `.id(useFrontCamera)` to recreate the
                // `MultipartCameraPreview` when the value flips, so
                // SwiftUI tears down the old `AVCaptureSession` and
                // builds a fresh one on the chosen device. Mirrors
                // Android's CoreAppViewModel.useFrontCamera flow.
                useFrontCamera = useFront
            case let .nfcActivate(payload):
                // Open reader mode for the TapTap exchange. The callback
                // forwards every `MobileEvent` the service emits
                // (`.nfcDataReceived`, hardware errors) back into core via
                // `sendHardwareEvent` — this closure IS the T2.2 event
                // wiring. Core's `NfcExchangeFlow` owns the handshake.
                nfcService.activate(payload: Data(payload)) { [weak self] event in
                    self?.sendHardwareEvent(event)
                }
            case let .nfcSendApdu(data):
                nfcService.sendApdu(data: Data(data))
            case .nfcDeactivate:
                nfcService.deactivate()
            case .accelerometerStart:
                startAccelerometerCapture()
            case .accelerometerStop:
                AccelerometerProximityService.shared.stop()
            default:
                // BLE / audio-proximity are handled in `handleBleCommand` /
                // `handleAudioCommand`. Any remaining command is a no-op on
                // iOS.
                break
            }
        }
    }

    /// Try the out-of-switch command helpers (BLE, audio, then location) in
    /// turn. Returns `true` as soon as one handles `command`, so the caller
    /// can `continue`. Folding these into one call keeps
    /// `handleExchangeCommands` within SwiftLint's complexity budget.
    private func handleTransportCommand(_ command: CommandDTO) -> Bool {
        handleBleCommand(command) || handleAudioCommand(command)
            || handleLocationCommand(command)
    }

    /// ADR-051 capture-at-exchange: grab a one-shot location fix and report it
    /// back so the engine records `set_exchange_location`. The service answers
    /// `permissionDenied`/`hardwareUnavailable` when no fix is possible, which
    /// clears core's pending capture. Extracted to keep `handleExchangeCommands`
    /// within SwiftLint's complexity budget.
    private func handleLocationCommand(_ command: CommandDTO) -> Bool {
        guard case let .locationRequest(timeoutMs) = command else { return false }
        locationRequestInFlight = true
        locationService.requestOneShot(timeoutMs: timeoutMs) { [weak self] event in
            DispatchQueue.main.async {
                self?.locationRequestInFlight = false
                self?.sendHardwareEvent(event)
            }
        }
        return true
    }

    /// Dispatch the engine-driven BLE exchange commands (ADR-031) to the
    /// lazily-activated `bleService`, forwarding every `MobileEvent` back via
    /// `sendHardwareEvent`. Returns `true` when `command` was a BLE command
    /// (and was handled here), `false` otherwise so the caller's main switch
    /// can take it. Split out to keep `handleExchangeCommands` within
    /// SwiftLint's cyclomatic-complexity budget.
    private func handleBleCommand(_ command: CommandDTO) -> Bool {
        switch command {
        case let .bleStartAdvertising(serviceUuid, payload):
            // Responder side (P5c): advertise the 128-bit service UUID plus
            // the role token as a 32-bit service UUID, and stand up the GATT
            // server. Core's `BleExchangeFlow` owns the handshake.
            activateBleIfNeeded()
            bleService.startAdvertising(serviceUuid: serviceUuid, payload: Data(payload))
        case let .bleStartScanning(serviceUuid):
            activateBleIfNeeded()
            bleService.startScanning(serviceUuid: serviceUuid)
        case .bleStopScanning:
            bleService.stopScanning()
        case let .bleConnect(deviceId):
            bleService.connect(deviceId: deviceId)
        case let .bleWriteCharacteristic(uuid, data):
            // A write to a responder-notify characteristic is a peripheral
            // push; everything else is a central GATT write. The service
            // routes on `BleUuids.peripheralNotifyChars`.
            bleService.writeCharacteristic(uuid: uuid, data: Data(data))
        case let .bleReadCharacteristic(uuid):
            bleService.readCharacteristic(uuid: uuid)
        case .bleDisconnect:
            bleService.disconnect()
        default:
            return false
        }
        return true
    }

    /// Dispatch the ultrasonic audio-proximity commands (ADR-031) to the
    /// shared `AudioProximityService`, mirroring Android's
    /// `AudioEmit/Listen/Stop` wiring. `AudioListenForResponse` records and
    /// replies with `MobileEvent.audioSamplesRecorded`; `AudioEmitChallenge`
    /// just plays the challenge tone (blocking, so it runs off the main
    /// thread). Returns `true` when `command` was an audio command, `false`
    /// otherwise so the caller's main switch can take it. Split out to keep
    /// `handleExchangeCommands` within SwiftLint's complexity budget.
    private func handleAudioCommand(_ command: CommandDTO) -> Bool {
        switch command {
        case let .audioEmitChallenge(samples, sampleRate):
            // `emitSignal` schedules the buffer and blocks for its duration —
            // never call it on the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AudioProximityService.shared.emitSignal(samples: samples, sampleRate: sampleRate)
            }
        case let .audioListenForResponse(timeoutMs, sampleRate):
            AudioProximityService.shared.receiveSignal(
                timeoutMs: timeoutMs, sampleRate: sampleRate
            ) { [weak self] samples, recordedRate in
                self?.sendHardwareEvent(
                    .audioSamplesRecorded(samples: samples, sampleRate: recordedRate)
                )
            }
        case .audioStop:
            AudioProximityService.shared.stop()
        default:
            return false
        }
        return true
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

    /// TapHoverShake shake stage: stream accelerometer readings and route each
    /// back to core (which builds + cross-correlates the envelope). The motion
    /// handler fires off the main actor, so hop back before touching core.
    private func startAccelerometerCapture() {
        AccelerometerProximityService.shared.start { [weak self] timestampMs, xMilliG, yMilliG, zMilliG in
            Task { @MainActor in
                self?.sendHardwareEvent(
                    .accelerometerData(
                        timestampMs: timestampMs,
                        xMilliG: xMilliG,
                        yMilliG: yMilliG,
                        zMilliG: zMilliG
                    )
                )
            }
        }
    }

    private func sendHardwareEvent(_ event: MobileEvent) {
        do {
            let resultJson = try appEngine.handleHardwareEvent(event: event)
            guard let resultData = resultJson.data(using: .utf8) else { return }
            // core 0.51.44+: handleHardwareEvent returns
            // `{"action_result": <ActionResult>|null, "commands": [<CommandDTO>]}`.
            // The commands carry the protocol/lifecycle work the event produced
            // (previously stranded); action_result is null when the event only
            // advanced an engine-held machine.
            let envelope = try coreJSONDecoder.decode(HardwareEventEnvelope.self, from: resultData)
            if let result = envelope.actionResult {
                applyResult(result)
            }
            if !envelope.commands.isEmpty {
                handleExchangeCommands(envelope.commands)
            }
        } catch {
            #if DEBUG
                print("AppViewModel: failed to send hardware event: \(error)")
            #endif
        }
    }
}

/// Envelope returned by `PlatformAppEngine.handleHardwareEvent` (core 0.51.44+):
/// `{"action_result": <ActionResult>|null, "commands": [<CommandDTO>]}`.
///
/// `actionResult` is optional — `nil` when the event only advanced an
/// engine-held machine (e.g. a multi-stage tick). `commands` carries every
/// `Command` the event produced so the frontend executes it on the hardware
/// (previously stranded in core's pending queue). Module-internal so the
/// biometric-unlock caller in `VauchiViewModel` shares it.
struct HardwareEventEnvelope: Decodable {
    let actionResult: ActionResult?
    let commands: [CommandDTO]

    enum CodingKeys: String, CodingKey {
        case actionResult = "action_result"
        case commands
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
