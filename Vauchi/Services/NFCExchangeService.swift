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

        // Phase 1: Send key offer
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

        tag.sendCommand(apdu: offerApdu) { [weak self] responseData, sw1, sw2, error in
            guard let self else { return }

            if let error {
                handleTagLoss(handshake: handshake, session: session, error: error)
                return
            }

            guard sw1 == 0x90, sw2 == 0x00 else {
                session.invalidate(errorMessage: "Key offer rejected (SW: \(String(format: "%02X%02X", sw1, sw2)))")
                return
            }

            // Parse response: [ack_len_hi, ack_len_lo, ack_bytes..., card_bytes...]
            guard responseData.count >= 2 else {
                session.invalidate(errorMessage: "Response too short")
                return
            }
            let ackLen = (Int(responseData[0]) << 8) | Int(responseData[1])
            guard responseData.count >= 2 + ackLen else {
                session.invalidate(errorMessage: "Invalid ack length")
                return
            }
            let ackBytes = responseData[2 ..< (2 + ackLen)]
            let encryptedCard = responseData[(2 + ackLen)...]

            // Phase 2: Process key ack + encrypted card
            let ourEncryptedCard: Data
            do {
                ourEncryptedCard = try handshake.processKeyAck(
                    theirAckBytes: Data(ackBytes),
                    theirEncryptedCard: Data(encryptedCard)
                )
            } catch {
                handleTagLoss(handshake: handshake, session: session, error: error)
                return
            }

            // Phase 3: Send our encrypted card
            let cardApdu = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: Self.insEncryptedCard,
                p1Parameter: 0x00,
                p2Parameter: 0x00,
                data: ourEncryptedCard,
                expectedResponseLength: -1
            )

            tag.sendCommand(apdu: cardApdu) { _, sw1_2, sw2_2, error2 in
                if let error2 {
                    self.handleTagLoss(handshake: handshake, session: session, error: error2)
                    return
                }

                guard sw1_2 == 0x90, sw2_2 == 0x00 else {
                    session.invalidate(errorMessage: "Card exchange rejected")
                    return
                }

                // Confirm send success
                do {
                    let result = try handshake.confirmSendSuccess()
                    session.alertMessage = "Exchange complete!"
                    session.invalidate()
                    self.complete(with: .success(result))
                } catch {
                    session.invalidate(errorMessage: "Exchange failed: \(error)")
                    self.complete(with: .error(error.localizedDescription))
                }
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
