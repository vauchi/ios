// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core queues `Command::ReloadTheme` once a content update applies themes
// (core!1937, private#733); the shell answers by applying the selected
// theme again, so a theme downloaded from the CDN reaches native theming
// without a restart.
//
// Traces to: features/remote_content.feature

@testable import Vauchi
import XCTest

@MainActor
final class ReloadThemeDispatchTests: XCTestCase {
    private var tempDir: URL!
    private var repo: VauchiRepository!
    private var viewModel: AppViewModel!
    private var reloads = 0

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Reload Theme Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
        reloads = 0
        viewModel.reloadTheme = { [unowned self] in reloads += 1 }
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReloadThemeDecodesAsItsOwnCommand() throws {
        let data = Data(#"{"commands":["ReloadTheme"]}"#.utf8)
        let commands = try JSONDecoder().decode(PresentationCommandEnvelope.self, from: data).commands

        guard case .reloadTheme = try XCTUnwrap(commands.first) else {
            return XCTFail("expected .reloadTheme, got \(commands)")
        }
    }

    func testReloadThemeAppliesTheSelectedThemeOnce() {
        viewModel.receivePresentationEnvelope(#"{"commands":["ReloadTheme"]}"#)

        XCTAssertEqual(reloads, 1)
        XCTAssertNil(viewModel.alertMessage, "the command must not surface as a presentation error")
    }

    func testAnEnvelopeWithoutReloadThemeLeavesTheThemeAlone() {
        viewModel.receivePresentationEnvelope(#"{"commands":["SomethingCoreAddedLater"]}"#)

        XCTAssertEqual(reloads, 0)
    }
}
