// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NFCExchangeService.swift
// CoreNFC reader for encrypted NFC contact exchange.
// iOS is always the reader/initiator (no HCE support on iOS).

import CoreNFC
import VauchiMobile

/// Drives the three-phase NFC handshake as the reader (initiator).
///
/// Usage:
/// 1. Create a `MobileNfcHandshake` via `VauchiMobile.createNfcInitiator()`
/// 2. Call `startExchange(session:)` to begin scanning
/// 3. Handle the result via the `onComplete` callback
class NFCExchangeService: NSObject, NFCTagReaderSessionDelegate {
    // MARK: - Types

    enum ExchangeResult {
        case success(MobileNfcExchangeResult)
        case relayFallback(exchangeId: Data)
        case error(String)
    }

    // MARK: - Properties

    private var nfcSession: NFCTagReaderSession?
    private var handshake: MobileNfcHandshake?
    private var onComplete: ((ExchangeResult) -> Void)?

    /// Vauchi NFC exchange AID: F0564155434849
    private static let vauchiAID = Data([0xF0, 0x56, 0x41, 0x55, 0x43, 0x48, 0x49])
    private static let insKeyOffer: UInt8 = 0xE0
    private static let insGetEncryptedCard: UInt8 = 0xE1
    private static let insEncryptedCard: UInt8 = 0xE2

    // MARK: - Public API

    /// Start NFC reader session for contact exchange.
    ///
    /// - Parameters:
    ///   - session: The initiator handshake session from VauchiMobile
    ///   - completion: Called with the exchange result (on main thread)
    func startExchange(
        session: MobileNfcHandshake,
        completion: @escaping (ExchangeResult) -> Void
    ) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(.error("NFC reading not available on this device"))
            return
        }

        handshake = session
        onComplete = completion

        nfcSession = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: nil
        )
        nfcSession?.alertMessage = "Hold your phone near the other device"
        nfcSession?.begin()
    }

    /// Cancel the current NFC session.
    func cancel() {
        nfcSession?.invalidate()
        nfcSession = nil
    }

    // MARK: - NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_: NFCTagReaderSession) {
        // Session is active, waiting for tag
    }

    func tagReaderSession(_: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nsError = error as NSError
        // Don't report user cancellation as an error
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            return
        }
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue {
            return
        }
        complete(with: .error(error.localizedDescription))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }

        guard case let .iso7816(iso7816Tag) = tag else {
            session.invalidate(errorMessage: "Unsupported tag type")
            return
        }

        session.connect(to: tag) { [weak self] error in
            if let error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }
            self?.performHandshake(with: iso7816Tag, session: session)
        }
    }

    // MARK: - Handshake Protocol

    private func performHandshake(with tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        guard let handshake else {
            session.invalidate(errorMessage: "No handshake session")
            return
        }

        let keyOfferData: Data
        do {
            keyOfferData = try handshake.createKeyOffer()
        } catch {
            session.invalidate(errorMessage: "Key offer failed: \(error)")
            return
        }

        let offerApdu = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Self.insKeyOffer,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: keyOfferData,
            expectedResponseLength: -1
        )

        tag.sendCommand(apdu: offerApdu) { [weak self] ackData, sw1, sw2, error in
            guard let self else { return }
            if let error {
                handleTagLoss(handshake: handshake, session: session, error: error)
                return
            }
            guard sw1 == 0x90, sw2 == 0x00 else {
                session.invalidate(errorMessage: "Key offer rejected (SW: \(String(format: "%02X%02X", sw1, sw2)))")
                return
            }
            fetchCardAndFinish(tag: tag, session: session, handshake: handshake, ackData: ackData)
        }
    }

    private func fetchCardAndFinish(
        tag: NFCISO7816Tag, session: NFCTagReaderSession,
        handshake: MobileNfcHandshake, ackData: Data
    ) {
        let getCardApdu = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Self.insGetEncryptedCard,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: -1
        )

        tag.sendCommand(apdu: getCardApdu) { [weak self] cardData, cardSw1, cardSw2, cardError in
            guard let self else { return }
            if let cardError {
                handleTagLoss(handshake: handshake, session: session, error: cardError)
                return
            }
            guard cardSw1 == 0x90, cardSw2 == 0x00 else {
                session.invalidate(errorMessage: "Failed to get encrypted card")
                return
            }

            let ourEncryptedCard: Data
            do {
                ourEncryptedCard = try handshake.processKeyAck(
                    theirAckBytes: ackData,
                    theirEncryptedCard: cardData
                )
            } catch {
                handleTagLoss(handshake: handshake, session: session, error: error)
                return
            }
            sendOurCard(tag: tag, session: session, handshake: handshake, cardData: ourEncryptedCard)
        }
    }

    private func sendOurCard(
        tag: NFCISO7816Tag, session: NFCTagReaderSession,
        handshake: MobileNfcHandshake, cardData: Data
    ) {
        let cardApdu = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: Self.insEncryptedCard,
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: cardData,
            expectedResponseLength: -1
        )

        tag.sendCommand(apdu: cardApdu) { [weak self] _, respSw1, respSw2, respError in
            guard let self else { return }
            if let respError {
                handleTagLoss(handshake: handshake, session: session, error: respError)
                return
            }
            guard respSw1 == 0x90, respSw2 == 0x00 else {
                session.invalidate(errorMessage: "Card exchange rejected")
                return
            }
            do {
                let result = try handshake.confirmSendSuccess()
                session.alertMessage = "Exchange complete!"
                session.invalidate()
                complete(with: .success(result))
            } catch {
                session.invalidate(errorMessage: "Exchange failed: \(error)")
                complete(with: .error(error.localizedDescription))
            }
        }
    }

    private func handleTagLoss(handshake: MobileNfcHandshake, session: NFCTagReaderSession, error: Error) {
        // Try relay fallback
        do {
            let exchangeId = try handshake.enterRelayFallback()
            session.invalidate(errorMessage: "Connection lost — continuing via relay")
            complete(with: .relayFallback(exchangeId: exchangeId))
        } catch {
            session.invalidate(errorMessage: "Exchange failed: \(error.localizedDescription)")
            complete(with: .error(error.localizedDescription))
        }
    }

    private func complete(with result: ExchangeResult) {
        DispatchQueue.main.async { [weak self] in
            self?.onComplete?(result)
            self?.onComplete = nil
            self?.handshake = nil
        }
    }
}
