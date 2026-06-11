// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Verifies `AppViewModel.applyResult` publishes the @Published state
// that drives the alert / toast hosts — with NO identity created, i.e.
// the onboarding tree, where core-driven `ShowAlert` (restore failure)
// and `ShowToast` were silently dropped because no host observed
// `AppViewModel` (`2026-06-11-ios-onboarding-alert-host-missing`;
// Android twin fixed in android!519). Per CC-23 the SwiftUI
// presentation itself is OS-tested — the contract worth pinning is
// that the published state flips with the exact payload.

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class ActionResultAlertToastTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // No createIdentity: PAE reports onboarding screens, matching
        // the tree whose missing hosts this change adds.
        repo = try VauchiRepository(dataDir: tempDir.path)
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_show_alert_publishes_title_and_message() {
        XCTAssertNil(viewModel.alertMessage)

        viewModel.applyResult(.showAlert(title: "Restore failed", message: "Wrong password"))

        XCTAssertEqual(viewModel.alertMessage?.title, "Restore failed")
        XCTAssertEqual(viewModel.alertMessage?.message, "Wrong password")
    }

    func test_show_toast_publishes_message_and_undo_action_id() {
        XCTAssertNil(viewModel.toastMessage)
        XCTAssertNil(viewModel.toastUndoActionId)

        viewModel.applyResult(.showToast(message: "Contact archived", undoActionId: "undo_archive_42"))

        XCTAssertEqual(viewModel.toastMessage, "Contact archived")
        XCTAssertEqual(viewModel.toastUndoActionId, "undo_archive_42")
    }

    func test_show_toast_without_undo_publishes_nil_undo_id() {
        viewModel.applyResult(.showToast(message: "Saved", undoActionId: nil))

        XCTAssertEqual(viewModel.toastMessage, "Saved")
        XCTAssertNil(viewModel.toastUndoActionId)
    }
}
