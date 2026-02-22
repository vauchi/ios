// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeepLinkHandler.swift
// Handles incoming vauchi:// deep links with a mandatory consent gate.
// Deep links are NEVER auto-processed. The user must explicitly confirm
// before any exchange payload is forwarded for processing.

import Foundation

/// Result of parsing a deep link URL.
enum DeepLinkResult {
    /// A valid exchange deep link that requires user consent before processing.
    case exchangePending(payload: String)

    /// The deep link URL was invalid or unsupported.
    case invalid(reason: String)
}

/// State of a deep link consent gate.
enum DeepLinkConsentState {
    /// Waiting for user to grant or deny consent.
    case pending

    /// User granted consent -- exchange may proceed.
    case granted

    /// User denied consent -- exchange must NOT proceed.
    case denied
}

/// Handles incoming `vauchi://` deep links with a mandatory consent gate.
///
/// Supported paths:
///   `vauchi://exchange/<payload>`
class DeepLinkHandler {
    private(set) var consentState: DeepLinkConsentState = .pending
    private(set) var pendingPayload: String?
    private(set) var exchangeProcessed: Bool = false

    /// Parse an incoming deep link URL.
    ///
    /// Returns `.exchangePending` if the URL is a valid exchange link.
    /// The exchange is NOT processed -- it is held pending until `grantConsent()` is called.
    ///
    /// Returns `.invalid` if the URL is malformed or unsupported.
    @discardableResult
    func handleDeepLink(url: URL) -> DeepLinkResult {
        guard url.scheme == "vauchi" else {
            return .invalid(reason: "Unsupported scheme: \(url.scheme ?? "nil")")
        }

        guard url.host == "exchange" else {
            return .invalid(reason: "Unsupported path: \(url.host ?? "nil")")
        }

        // Extract payload from path (first path component after host)
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let payload = pathComponents.first, !payload.isEmpty else {
            return .invalid(reason: "Missing exchange payload")
        }

        // Store payload but do NOT process -- consent required
        pendingPayload = payload
        consentState = .pending
        exchangeProcessed = false

        return .exchangePending(payload: payload)
    }

    /// Grant consent to process the pending exchange.
    ///
    /// Returns the exchange payload if consent is granted and a payload is pending.
    /// Returns nil if there is no pending payload.
    @discardableResult
    func grantConsent() -> String? {
        consentState = .granted
        let payload = pendingPayload
        if payload != nil {
            exchangeProcessed = true
        }
        return payload
    }

    /// Deny consent -- the pending exchange is discarded.
    func denyConsent() {
        consentState = .denied
        pendingPayload = nil
        exchangeProcessed = false
    }

    /// Reset the handler state (e.g., after an exchange completes or is dismissed).
    func reset() {
        consentState = .pending
        pendingPayload = nil
        exchangeProcessed = false
    }
}
