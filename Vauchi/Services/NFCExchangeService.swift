// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreNFC reader (transceive-shim only).
// iOS is always the reader/initiator (no HCE support on iOS).

import CoreNFC
import VauchiPlatform

/// Transceive-shim host for the NFC reader-side exchange path
/// (`activate(payload:callback:)` + `sendApdu(data:)` +
/// `deactivate()`). Pure APDU relay onto core's `ExchangeSession`
/// per ADR-031. Core's `NfcExchangeFlow`
/// (`core/vauchi-app/src/ui/exchange/nfc.rs`) owns the 3-phase
/// handshake state-machine; this service just relays bytes in and
/// `MobileEvent.nfcDataReceived` out. See
/// `_private/docs/designs/2026-05-19-nfc-phase2-ios-handler-prep.md`.
///
/// Consumer: `ExchangeCommandHandler` instantiates one
/// `NFCExchangeService` on first NFC command and dispatches the
/// `MobileCommand.nfcActivate` / `nfcSendApdu` / `nfcDeactivate`
/// arms onto it (Phase 3 of the NFC engine-graduation,
/// `ios!435` + later).
///
/// Legacy `startExchange(session:completion:)` flow + the
/// `MobileNfcHandshake`-based 3-phase state-machine retired
/// 2026-05-21 alongside `NfcExchangeView` (Phase 4 of the
/// engine-graduation, `ios!438`).
/// Dispatch seam for the three NFC reader commands. `AppViewModel`
/// holds this protocol type (not the concrete service) so the
/// command-dispatch wiring is unit-testable with a spy that records
/// calls instead of opening a real `NFCTagReaderSession` (CC-23: test
/// the bridge, not the OS NFC sheet). Production binds it to
/// `NFCExchangeService`.
protocol NFCExchangeDispatching: AnyObject {
    func activate(payload: Data, callback: @escaping (MobileEvent) -> Void)
    func sendApdu(data: Data)
    func deactivate()
}

class NFCExchangeService: NSObject, NFCTagReaderSessionDelegate, NFCExchangeDispatching {
    // MARK: - Properties

    private var transceiveSession: NFCTagReaderSession?
    private var transceiveTag: NFCISO7816Tag?
    private var transceiveCallback: ((MobileEvent) -> Void)?
    private var pendingActivatePayload: Data?

    /// INS byte used to wrap every outbound APDU. Mirrors Android's
    /// `NfcReaderService.transceiveOn`. The graduated responder
    /// (Phase 3b) no longer routes on INS — it reads the
    /// `Event::NfcDataReceived` payload regardless.
    private static let insKeyOffer: UInt8 = 0xE0

    // MARK: - NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_: NFCTagReaderSession) {
        // Session is active, waiting for tag.
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard session === transceiveSession else { return }
        let nsError = error as NSError
        // User cancellation surfaces as `hardwareUnavailable` so the
        // engine routes to a fallback screen rather than retry
        // indefinitely. All other invalidations surface as
        // `hardwareError` with the OS-provided description.
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            transceiveCallback?(.hardwareUnavailable(transport: "NFC"))
        } else {
            transceiveCallback?(.hardwareError(transport: "NFC", error: error.localizedDescription))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard session === transceiveSession else { return }
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }
        guard case let .iso7816(iso7816Tag) = tag else {
            session.invalidate(errorMessage: "Unsupported tag type")
            return
        }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                transceiveCallback?(.hardwareError(transport: "NFC", error: error.localizedDescription))
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }
            transceiveTag = iso7816Tag
            // Replay the pending initial APDU now that we're connected.
            if let payload = pendingActivatePayload {
                pendingActivatePayload = nil
                sendApduOn(tag: iso7816Tag, data: payload)
            }
        }
    }

    // MARK: - Transceive-shim API (ADR-031 — ExchangeCommandHandler consumer)

    /// Open an NFC reader session and, on first tag connect, transceive
    /// `payload` as the initial APDU. Subsequent APDU responses surface
    /// via `callback(.nfcDataReceived(data:))`. Session errors surface
    /// via `callback(.hardwareError/.hardwareUnavailable)`.
    ///
    /// Called from `ExchangeCommandHandler` on `MobileCommand.nfcActivate`.
    /// `payload` is the initiator's key offer (3-phase handshake's
    /// Phase 1 message).
    func activate(payload: Data, callback: @escaping (MobileEvent) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            callback(.hardwareUnavailable(transport: "NFC"))
            return
        }
        transceiveCallback = callback
        pendingActivatePayload = payload
        let session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: nil
        )
        session?.alertMessage = "Hold your phone near the other device"
        session?.begin()
        transceiveSession = session
    }

    /// Send `data` as an APDU on the currently-connected tag.
    /// Response bytes (plus SW1/SW2) surface via
    /// `callback(.nfcDataReceived(data:))`.
    ///
    /// Called from `ExchangeCommandHandler` on `MobileCommand.nfcSendApdu`.
    /// Invoking before `activate(payload:callback:)` connected a tag is
    /// a programming error from core's perspective — we report it as a
    /// hardware error so the engine can fail-fast rather than wedge.
    func sendApdu(data: Data) {
        guard let tag = transceiveTag else {
            transceiveCallback?(.hardwareError(transport: "NFC", error: "no tag connected"))
            return
        }
        sendApduOn(tag: tag, data: data)
    }

    /// Close the NFC reader session and clear all transceive state.
    ///
    /// Called from `ExchangeCommandHandler` on `MobileCommand.nfcDeactivate`.
    /// Idempotent — safe to call when no session is open.
    func deactivate() {
        transceiveSession?.invalidate()
        transceiveSession = nil
        transceiveTag = nil
        transceiveCallback = nil
        pendingActivatePayload = nil
    }

    private func sendApduOn(tag: NFCISO7816Tag, data: Data) {
        let apdu = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Self.insKeyOffer,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: data,
            expectedResponseLength: -1
        )
        tag.sendCommand(apdu: apdu) { [weak self] response, sw1, sw2, error in
            guard let self else { return }
            if let error {
                transceiveCallback?(.hardwareError(transport: "NFC", error: error.localizedDescription))
                return
            }
            var combined = response
            combined.append(sw1)
            combined.append(sw2)
            transceiveCallback?(.nfcDataReceived(data: combined))
        }
    }
}
