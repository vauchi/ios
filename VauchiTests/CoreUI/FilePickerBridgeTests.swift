// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FilePickerBridgeTests.swift
// Verifies the ADR-031 file-picker bridge wiring on iOS:
//
//   1. `AppViewModel.handleExchangeCommands` translates an
//      `ExchangeCommandDTO.filePickFromUser` into a non-nil
//      `pendingFilePick` carrying the correct purpose + MIME types.
//   2. `sendFilePickCancelled` clears that state.
//
// Replaces the previous UI test (FilePickerReachabilityUITests's
// MoreView path), which was racy: when `.fileImporter`'s binding
// flips true the system picker presents and covers any sentinel
// overlay before XCTest can query it.
//
// The bridge logic exercised here is entirely iOS-side. We feed
// `handleExchangeCommands` directly with a synthetic
// `ExchangeCommandDTO.filePickFromUser` instead of routing through
// real core — the upstream side (MoreEngine emits
// `ActionResult.ExchangeCommands{FilePickFromUser}`) is already
// covered by `core/vauchi-app/tests/it/file_picker_wiring_tests.rs`.

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class FilePickerBridgeTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "FilePicker Bridge Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Scenario: core emits `ExchangeCommand::FilePickFromUser` for
    /// `ImportContacts`. The bridge must store the purpose + accepted
    /// MIME types on `pendingFilePick`, which the
    /// `FilePickerModifier` then drives `.fileImporter` from.
    func testFilePickFromUserSetsPendingFilePick() {
        XCTAssertNil(
            viewModel.pendingFilePick,
            "pendingFilePick should start nil"
        )

        viewModel.handleExchangeCommands([
            .filePickFromUser(
                acceptedMimeTypes: ["text/vcard", "text/x-vcard"],
                purpose: .importContacts
            ),
        ])

        guard let pending = viewModel.pendingFilePick else {
            XCTFail("pendingFilePick should be non-nil after FilePickFromUser command")
            return
        }
        XCTAssertEqual(
            pending.purpose,
            .importContacts,
            "purpose should round-trip through the bridge"
        )
        XCTAssertEqual(
            pending.acceptedMimeTypes,
            ["text/vcard", "text/x-vcard"],
            "accepted MIME types should round-trip through the bridge"
        )
    }

    /// Scenario: `sendFilePickCancelled` clears pending state and
    /// emits the matching hardware event back to core. Covers the
    /// modifier's "user dismissed without our handler" cleanup path.
    func testSendFilePickCancelledClearsPendingState() {
        viewModel.handleExchangeCommands([
            .filePickFromUser(acceptedMimeTypes: ["text/vcard"], purpose: .importContacts),
        ])
        XCTAssertNotNil(
            viewModel.pendingFilePick,
            "precondition: pendingFilePick should be set by FilePickFromUser"
        )

        viewModel.sendFilePickCancelled()

        XCTAssertNil(
            viewModel.pendingFilePick,
            "sendFilePickCancelled must clear the pending pick state"
        )
    }
}
