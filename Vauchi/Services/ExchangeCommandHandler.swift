// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Dispatches ADR-031 exchange commands from core to platform hardware.
///
/// After each state-advancing call on `MobileExchangeSession`, drain pending
/// commands and pass them here. Results are reported back via
/// `applyHardwareEvent()` on the session.
final class ExchangeCommandHandler {
    private weak var session: MobileExchangeSession?

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

        // ── BLE ─────────────────────────────────────────────────────
        case .bleStartScanning:
            reportUnavailable(transport: "BLE")

        case .bleStartAdvertising:
            reportUnavailable(transport: "BLE")

        case .bleConnect:
            reportUnavailable(transport: "BLE")

        case .bleWriteCharacteristic:
            reportUnavailable(transport: "BLE")

        case .bleReadCharacteristic:
            reportUnavailable(transport: "BLE")

        case .bleDisconnect:
            break

        // ── NFC ─────────────────────────────────────────────────────
        case .nfcActivate:
            // NFC is handled separately via NFCExchangeService (ISO7816 APDU).
            // The command/event path isn't used for NFC on iOS — the NFC
            // reader session drives the protocol directly.
            reportUnavailable(transport: "NFC-command")

        case .nfcDeactivate:
            break
        }
    }

    // MARK: - Audio

    private func emitAudioChallenge(data: [UInt8]) {
        guard let service = AudioProximityService.shared else {
            reportUnavailable(transport: "Audio")
            return
        }
        let floatData = data.map { Float($0) / 255.0 }
        service.emitSignal(samples: floatData, sampleRate: 44100) { [weak self] error in
            if let error {
                self?.reportError(transport: "Audio", error: error)
            }
        }
    }

    private func listenForAudioResponse(timeoutMs: UInt64) {
        guard let service = AudioProximityService.shared else {
            reportUnavailable(transport: "Audio")
            return
        }
        service.receiveSignal(timeoutMs: timeoutMs, sampleRate: 44100) { [weak self] result in
            guard let self, let session else { return }
            switch result {
            case let .success(samples):
                let data = samples.map { UInt8(clamping: Int($0 * 255.0)) }
                try? session.applyHardwareEvent(
                    event: .audioResponseReceived(data: data)
                )
                drainAndDispatch()
            case let .failure(error):
                reportError(transport: "Audio", error: error.localizedDescription)
            }
        }
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
}
