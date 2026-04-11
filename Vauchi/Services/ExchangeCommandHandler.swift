// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
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
    private func dispatch(_ command: MobileExchangeCommand) {
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
        case let .audioEmitChallenge(data):
            emitAudioChallenge(data: data)

        case let .audioListenForResponse(timeoutMs):
            listenForAudioResponse(timeoutMs: timeoutMs)

        case .audioStop:
            // Audio operations are one-shot — no persistent state to stop.
            break

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

        // ── Tier 0 commands (active after bindings bump) ───────────
        // AccelerometerStart/Stop, RelayEscrowDeposit/Check/Retrieve,
        // ShowShareSheet — handled via @unknown default until
        // vauchi-platform-swift is regenerated with new variants.
        @unknown default:
            break
        }
    }

    // MARK: - Audio

    private func emitAudioChallenge(data: Data) {
        let verifier = MobileProximityVerifier.new(handler: AudioProximityService.shared)
        let result = verifier.emitChallenge(challenge: Array(data))
        if !result.success {
            reportError(transport: "Audio", error: result.error)
        }
    }

    private func listenForAudioResponse(timeoutMs: UInt64) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let session else { return }
            let verifier = MobileProximityVerifier.new(handler: AudioProximityService.shared)
            let received = verifier.listenForResponse(timeoutMs: timeoutMs)
            DispatchQueue.main.async {
                try? session.applyHardwareEvent(
                    event: .audioResponseReceived(data: Data(received))
                )
                self.drainAndDispatch()
            }
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
