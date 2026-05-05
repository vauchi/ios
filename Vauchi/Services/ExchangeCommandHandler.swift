// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import UIKit
import VauchiPlatform

/// Dispatches ADR-031 exchange commands from core to platform hardware.
///
/// After each state-advancing call on `MobileExchangeSession`, drain pending
/// commands and pass them here. Results are reported back via
/// `applyHardwareEvent()` on the session.
final class ExchangeCommandHandler {
    private weak var session: MobileExchangeSession?
    private lazy var bleService: BleExchangeService = {
        let service = BleExchangeService()
        service.activate { [weak self] event in
            guard let self, let session else { return }
            try? session.applyHardwareEvent(event: event)
            drainAndDispatch()
        }
        return service
    }()

    /// directSendService is instantiated on first DirectSend command.
    /// Kept alive so that cancel() can interrupt a pending accept().
    private var directSendService: DirectSendService?

    private let audioService = AudioProximityService.shared

    /// Snapshot of `UIScreen.main.brightness` taken on the first
    /// `SetScreenBrightness { level: Some(_) }` command and restored
    /// when `SetScreenBrightness { level: None }` arrives. Per
    /// `2026-05-04-exchange-command-screen-presentation` Phase 2a —
    /// the frontend owns the snapshot/restore lifecycle so core only
    /// has to express intent.
    private var savedBrightness: CGFloat?

    init(session: MobileExchangeSession) {
        self.session = session
    }

    /// Process all pending commands from the session.
    ///
    /// Call after `generateQr()`, `processQr()`, `performKeyAgreement()`, etc.
    func drainAndDispatch() {
        guard let session else { return }
        let commands = session.drainPendingCommands()
        for command in commands {
            dispatch(command)
        }
    }

    /// Dispatch a single exchange command to the appropriate platform service.
    private func dispatch(_ command: MobileCommand) {
        switch command {
        // ── QR ──────────────────────────────────────────────────────
        case .qrDisplay:
            // QR display is handled by the view layer (FaceToFaceExchangeView)
            // — no platform action needed.
            break

        case .qrRequestScan:
            // Camera scanning is handled by HeadlessQrScanner in the view layer.
            break

        // ── Audio (ultrasonic proximity) ────────────────────────────
        case let .audioEmitChallenge(samples, sampleRate):
            emitAudioChallenge(samples: samples, sampleRate: sampleRate)

        case let .audioListenForResponse(timeoutMs, sampleRate):
            listenForAudioResponse(timeoutMs: timeoutMs, sampleRate: sampleRate)

        case .audioStop:
            audioService.stop()

        // ── BLE (CoreBluetooth) ─────────────────────────────────────
        case let .bleStartScanning(serviceUuid):
            bleService.startScanning(serviceUuid: serviceUuid)

        case let .bleStartAdvertising(serviceUuid, _):
            bleService.startAdvertising(serviceUuid: serviceUuid)

        case let .bleConnect(deviceId):
            bleService.connect(deviceId: deviceId)

        case let .bleWriteCharacteristic(uuid, data):
            bleService.writeCharacteristic(uuid: uuid, data: data)

        case let .bleReadCharacteristic(uuid):
            bleService.readCharacteristic(uuid: uuid)

        case .bleDisconnect:
            bleService.disconnect()

        // ── NFC ─────────────────────────────────────────────────────
        case .nfcActivate:
            // NFC is handled separately via NFCExchangeService (ISO7816 APDU).
            // The command/event path isn't used for NFC on iOS — the NFC
            // reader session drives the protocol directly.
            reportUnavailable(transport: "NFC-command")

        case .nfcDeactivate:
            break

        // ── DirectSend (USB cable) ──────────────────────────────────
        // BINDINGS_BUMP: uncomment when vauchi-platform-swift gains the
        // .directSend(payload:isInitiator:) variant. Until then the command
        // falls through to @unknown default.
        //
        // case let .directSend(payload, isInitiator):
        //     startDirectSend(payload: Array(payload), isInitiator: isInitiator)

        // ── Screen presentation hardware (multi-stage exchange) ────
        // BINDINGS_BUMP: uncomment when vauchi-platform-swift is
        // regenerated against core 0.45.0 (introduces
        // .setScreenBrightness(level:) and .setIdleTimerDisabled(disabled:)).
        // Phase 2a of `2026-05-04-exchange-command-screen-presentation` —
        // the helper methods below already implement the platform calls
        // they will dispatch to, so the only change at bindings-bump
        // time is to remove the comment markers and let these match arms
        // take over from FaceToFaceExchangeView's onAppear/onDisappear.
        //
        // case let .setScreenBrightness(level):
        //     setScreenBrightness(level: level.map { CGFloat($0) })
        //
        // case let .setIdleTimerDisabled(disabled):
        //     setIdleTimerDisabled(disabled)

        // ── Tier 0 commands (active after bindings bump) ───────────
        // AccelerometerStart/Stop, RelayEscrowDeposit/Check/Retrieve,
        // ShowShareSheet, DirectSend, SetScreenBrightness,
        // SetIdleTimerDisabled — handled via @unknown default until
        // vauchi-platform-swift is regenerated with new variants.
        @unknown default:
            break
        }
    }

    // MARK: - Screen presentation (ADR-031, Phase 2a)

    //
    // Drive `UIScreen.brightness` and `UIApplication.isIdleTimerDisabled`
    // from core's `SetScreenBrightness` / `SetIdleTimerDisabled` commands.
    // FaceToFaceExchangeView currently owns this in its `onAppear` /
    // `onDisappear`; once the engine emits these commands and the
    // bindings bump unlocks the dispatch arms above, the view becomes a
    // thin `CoreScreenView("MultiStageExchange")` wrapper (Phase 3).

    /// Set screen brightness. `Some(level)` clamps to 0.0–1.0 and
    /// snapshots the prior platform value on the first call so a
    /// subsequent `nil` restores it. `nil` restores from the saved
    /// snapshot if present, or no-ops if no snapshot exists (defensive
    /// — handles a `None` arriving without a preceding `Some`).
    func setScreenBrightness(level: CGFloat?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let level {
                if savedBrightness == nil {
                    savedBrightness = UIScreen.main.brightness
                }
                UIScreen.main.brightness = max(0.0, min(1.0, level))
            } else if let prior = savedBrightness {
                UIScreen.main.brightness = prior
                savedBrightness = nil
            }
        }
    }

    /// Toggle the platform idle timer. Idempotent — the underlying
    /// `UIApplication.isIdleTimerDisabled` setter is no-op on a
    /// redundant value. Marshalled to the main thread because UIKit
    /// requires it.
    func setIdleTimerDisabled(_ disabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }

    // MARK: - DirectSend

    private func startDirectSend(payload: [UInt8], isInitiator: Bool) {
        let service = DirectSendService()
        directSendService = service
        service.setEventCallback { [weak self] event in
            guard let self, let session else { return }
            try? session.applyHardwareEvent(event: event)
            drainAndDispatch()
        }
        service.exchange(payload: payload, isInitiator: isInitiator)
    }

    // MARK: - Audio (ADR-031 command/event protocol)

    private func emitAudioChallenge(samples: [Float], sampleRate: UInt32) {
        // emitSignal blocks for the playback duration, so dispatch off the
        // command-drain thread to avoid stalling other commands.
        DispatchQueue.global(qos: .userInitiated).async { [audioService] in
            _ = audioService.emitSignal(samples: samples, sampleRate: sampleRate)
        }
    }

    private func listenForAudioResponse(timeoutMs: UInt64, sampleRate: UInt32) {
        audioService.receiveSignal(timeoutMs: timeoutMs, sampleRate: sampleRate) { [weak self] samples, recordedRate in
            guard let self, let session else { return }
            try? session.applyHardwareEvent(
                event: .audioSamplesRecorded(samples: samples, sampleRate: recordedRate)
            )
            drainAndDispatch()
        }
    }

    // MARK: - Relay Escrow

    private func depositToEscrow(gateHash _: Data, slotHash _: Data, blob _: Data, ttl _: UInt32) {
        // TODO: POST to relay OHTTP endpoint with EscrowMessage::Put
        // On success: no event needed (fire-and-forget deposit)
        // On failure: report RelayEscrowFailed
        reportError(transport: "RelayEscrow", error: "not yet implemented")
    }

    private func checkEscrow(gateHash _: Data) {
        // TODO: POST to relay OHTTP endpoint with EscrowMessage::Count
        // When count >= 2: report RelayEscrowReady
        // Otherwise: schedule retry after delay
        reportError(transport: "RelayEscrow", error: "not yet implemented")
    }

    private func retrieveFromEscrow(gateHash _: Data, slotHash _: Data) {
        // TODO: POST to relay OHTTP endpoint with EscrowMessage::Get
        // On Blob response: pass blob back to core for decryption
        // On error: report RelayEscrowFailed
        reportError(transport: "RelayEscrow", error: "not yet implemented")
    }

    // MARK: - Share Sheet

    private func showShareSheet(url _: String) {
        // TODO: Present UIActivityViewController with the exchange URL
        // On completion: report LinkShared event
        // On cancel: no event (user stays on share screen)
    }

    // MARK: - Feedback

    private func reportUnavailable(transport: String) {
        guard let session else { return }
        try? session.applyHardwareEvent(
            event: .hardwareUnavailable(transport: transport)
        )
        drainAndDispatch()
    }

    private func reportError(transport: String, error: String) {
        guard let session else { return }
        try? session.applyHardwareEvent(
            event: .hardwareError(transport: transport, error: error)
        )
        drainAndDispatch()
    }

    private func reportPermissionDenied(transport: String) {
        guard let session else { return }
        do {
            try session.applyHardwareEvent(
                event: .permissionDenied(transport: transport)
            )
        } catch {
            NSLog("[Vauchi] Failed to report permission denied: \(error)")
        }
        drainAndDispatch()
    }
}
