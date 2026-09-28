// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// A failure the shell cannot hand back to Core — an envelope it cannot
// decode — still reaches the user as Core-localized copy, never as the
// error's own description (vauchi/private#308 Defect 2: the alert used to
// print `String(describing: error)`; ADR-045 Amendment 1, DC-05).
//
// Traces to: features/generic_presentation_protocol.feature

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class PresentationErrorAlertTests: XCTestCase {
    private var tempDir: URL!
    private var repo: VauchiRepository!
    private var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Presentation Error Alert Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUndecodableEnvelopeShowsCoreLocalizedCopy() throws {
        viewModel.receivePresentationEnvelope("{not json")

        let alert = try XCTUnwrap(viewModel.alertMessage)
        XCTAssertEqual(alert.title, LocalizationService.shared.t("error.title"))
        XCTAssertEqual(alert.message, LocalizationService.shared.t("error.generic"))
        XCTAssertNotEqual(alert.message, "error.generic", "copy must resolve, not echo the key")
        XCTAssertFalse(alert.message.contains("Error("), "no Swift error description: \(alert.message)")
        XCTAssertFalse(alert.message.contains("dataCorrupted"), "no decoder detail: \(alert.message)")
    }
}
