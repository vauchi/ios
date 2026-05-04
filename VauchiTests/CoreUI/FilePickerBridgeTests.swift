// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FilePickerBridgeTests.swift
// Verifies that the ADR-031 file-picker bridge fires correctly:
// when `AppViewModel.handleAction` receives an `import_contacts`
// ActionPressed on `AppScreen::More`, core returns
// `ActionResult.exchangeCommands{FilePickFromUser}`, and
// `handleExchangeCommands` sets `pendingFilePick`.
//
// Replaces the previous UI test (FilePickerReachabilityUITests's
// MoreView path), which was racy: when `.fileImporter`'s binding
// flips true the system picker presents and covers any sentinel
// overlay before XCTest can query it. The unit test exercises the
// same bridge end-to-end through real core code (no mocks) without
// relying on the OS picker actually opening — that part is
// SwiftUI's responsibility once `pendingFilePick` is non-nil.

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

    /// Scenario: user taps "Import Contacts" in MoreView. The button
    /// navigates the engine to AppScreen::More and emits
    /// `import_contacts`. MoreEngine returns a FilePickFromUser
    /// command. `pendingFilePick` must flip non-nil with
    /// `purpose == .importContacts`.
    func testImportContactsActionSetsPendingFilePick() {
        XCTAssertNil(
            viewModel.pendingFilePick,
            "pendingFilePick should start nil"
        )

        viewModel.navigateTo(screenJson: "\"More\"")
        viewModel.handleAction(.actionPressed(actionId: "import_contacts"))

        guard let pending = viewModel.pendingFilePick else {
            XCTFail("pendingFilePick should be non-nil after MoreEngine emits FilePickFromUser")
            return
        }
        XCTAssertEqual(
            pending.purpose,
            .importContacts,
            "purpose should match the FilePickPurpose::ImportContacts emitted by core"
        )
        XCTAssertFalse(
            pending.acceptedMimeTypes.isEmpty,
            "core must emit at least one accepted MIME type for vCard import"
        )
        XCTAssertTrue(
            pending.acceptedMimeTypes.contains("text/vcard"),
            "expected text/vcard among accepted types, got \(pending.acceptedMimeTypes)"
        )
    }

    /// Scenario: `sendFilePickCancelled` clears pending state and
    /// emits the matching hardware event back to core. Verifies the
    /// modifier's "user dismissed without our handler" cleanup path.
    func testSendFilePickCancelledClearsPendingState() {
        viewModel.navigateTo(screenJson: "\"More\"")
        viewModel.handleAction(.actionPressed(actionId: "import_contacts"))
        XCTAssertNotNil(
            viewModel.pendingFilePick,
            "precondition: pendingFilePick should be set by the import_contacts action"
        )

        viewModel.sendFilePickCancelled()

        XCTAssertNil(
            viewModel.pendingFilePick,
            "sendFilePickCancelled must clear the pending pick state"
        )
    }
}
