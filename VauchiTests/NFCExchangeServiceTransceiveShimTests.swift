// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NFCExchangeServiceTransceiveShimTests.swift
// Unit tests for the transceive-shim API added in Phase 2 of the
// NFC engine-graduation
// (_private/docs/problems/2026-05-19-nfc-exchange-engine-graduation).
//
// Scope: the parts of the new `activate(payload:callback:)` /
// `sendApdu(data:)` / `deactivate()` API that are testable on the
// iOS simulator — i.e., the hardware-unavailable code path and the
// defensive "no tag connected" / fresh-service-deactivate cases.
//
// **Out of scope (per CC-23 + prep brief §"Risks the executing
// session should watch")**: any test that pretends CoreNFC is
// available. `NFCTagReaderSession.readingAvailable` returns `false`
// on simulators, so the post-readingAvailable code paths (tag
// detect, APDU transceive, delegate callbacks) cannot be exercised
// here without injecting a transport protocol shim. The end-to-end
// transceive cycle is covered by Phase 6 physical-device cycles
// (Tier B) — see the engine-graduation record's Phase 6.

@testable import Vauchi
import VauchiPlatform
import XCTest

final class NFCExchangeServiceTransceiveShimTests: XCTestCase {
    var service: NFCExchangeService!

    override func setUp() {
        super.setUp()
        service = NFCExchangeService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    /// On the simulator (where `NFCTagReaderSession.readingAvailable`
    /// is `false`), `activate(payload:callback:)` must surface a
    /// `hardwareUnavailable(transport: "NFC")` event synchronously
    /// — the engine relies on this to route to a fallback screen
    /// rather than wait for a tag that will never tap.
    func testActivateOnSimulatorSynchronouslyReportsHardwareUnavailable() {
        var receivedEvents: [MobileEvent] = []
        service.activate(payload: Data([0x01, 0x02, 0x03])) { event in
            receivedEvents.append(event)
        }

        XCTAssertEqual(
            receivedEvents.count,
            1,
            "activate on a simulator must invoke the callback exactly once"
        )
        guard case let .hardwareUnavailable(transport) = receivedEvents[0] else {
            XCTFail(
                "expected .hardwareUnavailable, got \(receivedEvents[0])"
            )
            return
        }
        XCTAssertEqual(
            transport,
            "NFC",
            "hardwareUnavailable transport tag must be 'NFC' so core's NfcExchangeFlow routes the event (it filters on transport == \"nfc\" case-insensitive)"
        )
    }

    /// `deactivate()` on a fresh service (no prior activate) must
    /// be a safe no-op. Engine may emit `nfcDeactivate` after a
    /// hardware-unavailable bail-out, before the engine knows the
    /// session was never opened.
    func testDeactivateOnFreshServiceIsSafe() {
        service.deactivate()
        // Surviving the call is the assertion. Second deactivate
        // must also be safe (idempotent contract).
        service.deactivate()
        XCTAssertTrue(true, "deactivate must be idempotent on a fresh service")
    }

    /// `sendApdu(data:)` on a fresh service (no prior activate)
    /// must not crash. With no callback registered the event is
    /// silently dropped; the engine has already moved past the
    /// activate failure and won't expect a response.
    func testSendApduWithoutActivateIsSafe() {
        service.sendApdu(data: Data([0x90, 0x00]))
        XCTAssertTrue(true, "sendApdu must not crash on a fresh service")
    }
}
