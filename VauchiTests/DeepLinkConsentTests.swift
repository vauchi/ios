// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeepLinkConsentTests.swift
// Tests for deep link consent gate (SP-9)
// Critical security invariant: deep links MUST require explicit user consent
// before any exchange is processed. Auto-processing is forbidden.

@testable import Vauchi
import XCTest

final class DeepLinkConsentTests: XCTestCase {
    var handler: DeepLinkHandler!

    override func setUpWithError() throws {
        handler = DeepLinkHandler()
    }

    override func tearDownWithError() throws {
        handler = nil
    }

    // MARK: - Consent Gate Tests

    /// Scenario: Deep link requires consent before exchange is processed
    func testDeepLinkRequiresConsentBeforeExchange() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/abc123payload"))
        let result = handler.handleDeepLink(url: url)

        // Deep link is parsed but NOT processed
        guard case let .exchangePending(payload) = result else {
            XCTFail("Expected exchangePending result, got \(result)")
            return
        }
        XCTAssertEqual(payload, "abc123payload")

        // Exchange must NOT be processed yet
        XCTAssertFalse(handler.exchangeProcessed,
                       "Exchange must not be auto-processed")
        XCTAssertEqual(handler.consentState, .pending,
                       "Consent must be PENDING after deep link received")
        XCTAssertNotNil(handler.pendingPayload,
                        "Payload must be held pending")
    }

    /// Scenario: Exchange is processed only after consent is granted
    func testExchangeProcessedOnlyAfterConsentGranted() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/payload456"))
        handler.handleDeepLink(url: url)

        // Before consent
        XCTAssertFalse(handler.exchangeProcessed)

        // Grant consent
        let payload = handler.grantConsent()

        XCTAssertEqual(payload, "payload456")
        XCTAssertTrue(handler.exchangeProcessed,
                      "Exchange should be processed after consent")
        XCTAssertEqual(handler.consentState, .granted)
    }

    /// Scenario: Exchange is discarded when consent is denied
    func testExchangeDiscardedWhenConsentDenied() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/sensitive-data"))
        handler.handleDeepLink(url: url)

        handler.denyConsent()

        XCTAssertFalse(handler.exchangeProcessed,
                       "Exchange must not be processed on denial")
        XCTAssertEqual(handler.consentState, .denied)
        XCTAssertNil(handler.pendingPayload,
                     "Pending payload must be cleared on denial")
    }

    /// Scenario: Consent state is pending immediately after deep link received
    func testConsentStatePendingAfterDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/test"))
        handler.handleDeepLink(url: url)

        XCTAssertEqual(handler.consentState, .pending)
    }

    // MARK: - URL Parsing Tests

    /// Scenario: Valid exchange deep link is parsed correctly
    func testValidExchangeDeepLinkParsed() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/wb%3A%2F%2FsomeBase64Data"))
        let result = handler.handleDeepLink(url: url)

        guard case let .exchangePending(payload) = result else {
            XCTFail("Expected exchangePending, got \(result)")
            return
        }
        // URL decodes %3A -> : but %2F stays as path segment
        XCTAssertFalse(payload.isEmpty, "Payload should not be empty")
    }

    /// Scenario: Invalid scheme returns invalid result
    func testInvalidSchemeReturnsInvalid() throws {
        let url = try XCTUnwrap(URL(string: "https://exchange/payload"))
        let result = handler.handleDeepLink(url: url)

        guard case let .invalid(reason) = result else {
            XCTFail("Expected invalid result for https scheme")
            return
        }
        XCTAssertTrue(reason.contains("scheme"),
                      "Reason should mention scheme: \(reason)")
    }

    /// Scenario: Unsupported path returns invalid result
    func testUnsupportedPathReturnsInvalid() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://settings/something"))
        let result = handler.handleDeepLink(url: url)

        guard case let .invalid(reason) = result else {
            XCTFail("Expected invalid result for unsupported path")
            return
        }
        XCTAssertTrue(reason.contains("path"),
                      "Reason should mention path: \(reason)")
    }

    /// Scenario: Missing payload returns invalid result
    func testMissingPayloadReturnsInvalid() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange"))
        let result = handler.handleDeepLink(url: url)

        guard case let .invalid(reason) = result else {
            XCTFail("Expected invalid result for missing payload")
            return
        }
        XCTAssertTrue(reason.contains("payload"),
                      "Reason should mention payload: \(reason)")
    }

    /// Scenario: Empty payload returns invalid result
    func testEmptyPayloadReturnsInvalid() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/"))
        let result = handler.handleDeepLink(url: url)

        guard case .invalid = result else {
            XCTFail("Expected invalid result for empty payload")
            return
        }
    }

    // MARK: - State Management Tests

    /// Scenario: Granting consent without pending payload returns nil
    func testGrantConsentWithoutPendingReturnsNil() {
        let result = handler.grantConsent()

        XCTAssertNil(result, "No pending payload should return nil")
    }

    /// Scenario: Reset clears all state
    func testResetClearsAllState() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/data"))
        handler.handleDeepLink(url: url)
        _ = handler.grantConsent()

        handler.reset()

        XCTAssertEqual(handler.consentState, .pending)
        XCTAssertNil(handler.pendingPayload)
        XCTAssertFalse(handler.exchangeProcessed)
    }

    /// Scenario: Second deep link replaces first pending payload
    func testSecondDeepLinkReplacesFirst() throws {
        try handler.handleDeepLink(url: XCTUnwrap(URL(string: "vauchi://exchange/first")))
        try handler.handleDeepLink(url: XCTUnwrap(URL(string: "vauchi://exchange/second")))

        XCTAssertEqual(handler.pendingPayload, "second")
        XCTAssertFalse(handler.exchangeProcessed,
                       "Exchange must still require consent")
        XCTAssertEqual(handler.consentState, .pending)
    }

    // MARK: - Adversarial Input Tests (CC-14)

    /// Scenario: Extremely long payload does not crash
    func testExtremelyLongPayloadDoesNotCrash() throws {
        let longPayload = String(repeating: "a", count: 100_000)
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/\(longPayload)"))
        let result = handler.handleDeepLink(url: url)

        guard case .exchangePending = result else {
            XCTFail("Expected exchangePending for long payload")
            return
        }
        XCTAssertFalse(handler.exchangeProcessed)
    }

    /// Scenario: Unicode payload is handled without crash
    func testUnicodePayloadHandled() throws {
        let url = try XCTUnwrap(URL(string: "vauchi://exchange/hello%F0%9F%91%8Bworld"))
        let result = handler.handleDeepLink(url: url)

        guard case .exchangePending = result else {
            XCTFail("Expected exchangePending for unicode payload")
            return
        }
        XCTAssertFalse(handler.exchangeProcessed)
    }
}
