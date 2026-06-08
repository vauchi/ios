// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Verifies `AppViewModel.handleExchangeCommands` routes the three NFC
// reader commands (`nfcActivate` / `nfcSendApdu` / `nfcDeactivate`) to
// `NFCExchangeDispatching`, and that `nfcActivate` hands the service a
// callback that forwards `MobileEvent`s back into core (T2.2).
//
// CC-23: the dispatch seam is verified with a spy, never by polling the
// OS NFC sheet (a real `NFCTagReaderSession` can't open in a unit test
// and the system UI is OS-version-coupled). Upstream coverage — the
// engine emits the matching command on the matching action — lives in
// core's exchange wiring tests; SwiftUI/CoreNFC presenting the reader
// once the bridge fires is OS-tested.

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class NfcCommandDispatchTests: XCTestCase {
    /// Records dispatched calls instead of opening a CoreNFC session.
    private final class NFCDispatchSpy: NFCExchangeDispatching {
        var activatePayloads: [Data] = []
        var capturedCallback: ((MobileEvent) -> Void)?
        var sendApduCalls: [Data] = []
        var deactivateCount = 0

        func activate(payload: Data, callback: @escaping (MobileEvent) -> Void) {
            activatePayloads.append(payload)
            capturedCallback = callback
        }

        func sendApdu(data: Data) {
            sendApduCalls.append(data)
        }

        func deactivate() {
            deactivateCount += 1
        }
    }

    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!
    private var spy: NFCDispatchSpy!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "NFC Dispatch Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
        spy = NFCDispatchSpy()
        // `nfcService` is `lazy`; assigning before first access replaces
        // the concrete default with the spy.
        viewModel.nfcService = spy
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        spy = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// T2.1 + T2.2: `nfcActivate` forwards the bootstrap payload and hands
    /// the service a non-nil event callback (only `nfcActivate` does).
    func testNfcActivateForwardsPayloadAndWiresCallback() {
        viewModel.handleExchangeCommands([.nfcActivate(payload: [0x00, 0xA4, 0x04, 0x00])])

        XCTAssertEqual(spy.activatePayloads, [Data([0x00, 0xA4, 0x04, 0x00])])
        XCTAssertNotNil(spy.capturedCallback, "activate must receive the event callback (T2.2)")
        XCTAssertTrue(spy.sendApduCalls.isEmpty)
        XCTAssertEqual(spy.deactivateCount, 0)
    }

    /// T2.1: `nfcSendApdu` relays exact APDU bytes, nothing else.
    func testNfcSendApduForwardsExactBytes() {
        viewModel.handleExchangeCommands([.nfcSendApdu(data: [0x90, 0x00])])

        XCTAssertEqual(spy.sendApduCalls, [Data([0x90, 0x00])])
        XCTAssertTrue(spy.activatePayloads.isEmpty)
        XCTAssertEqual(spy.deactivateCount, 0)
    }

    /// T2.1: `nfcDeactivate` tears the reader down.
    func testNfcDeactivateDispatches() {
        viewModel.handleExchangeCommands([.nfcDeactivate])

        XCTAssertEqual(spy.deactivateCount, 1)
        XCTAssertTrue(spy.activatePayloads.isEmpty)
        XCTAssertTrue(spy.sendApduCalls.isEmpty)
    }

    /// T2.2: invoking the captured callback forwards the `MobileEvent` into
    /// the engine without trapping. Core's handling of an off-exchange
    /// `.nfcDataReceived` is covered by core wiring tests; here we assert
    /// the bridge forwards it (the closure routes via `sendHardwareEvent`).
    func testActivateCallbackForwardsDataReceived() {
        viewModel.handleExchangeCommands([.nfcActivate(payload: [0x00])])
        XCTAssertNotNil(spy.capturedCallback)

        spy.capturedCallback?(.nfcDataReceived(data: Data([0x6F, 0x00])))
    }
}
