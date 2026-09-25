// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// `--import-backup <path>` lets the store-screenshot UI test restore a
// fixture backup without driving the system document picker, which CC-23
// forbids. The launch argument only substitutes the file the user would
// have picked; Core still receives the same `filePickedFromUser` event.

@testable import Vauchi
import XCTest

@MainActor
final class DebugFilePickFixtureTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Fixture Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        AppViewModel.debugFilePickFixture = nil
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Launch argument parsing

    func testFixtureIsReadFromTheImportBackupArgument() {
        let url = AppViewModel.debugFilePickFixture(
            fromArguments: ["Vauchi", "--import-backup", "/tmp/seed.vauchibackup"]
        )

        XCTAssertEqual(url?.path, "/tmp/seed.vauchibackup")
    }

    func testNoFixtureWithoutTheArgument() {
        let url = AppViewModel.debugFilePickFixture(fromArguments: ["Vauchi", "--reset-for-testing"])

        XCTAssertNil(url)
    }

    func testNoFixtureWhenTheArgumentHasNoPath() {
        let url = AppViewModel.debugFilePickFixture(fromArguments: ["Vauchi", "--import-backup"])

        XCTAssertNil(url)
    }

    // MARK: - Answering FilePickFromUser

    func testReadableFixtureAnswersThePickWithoutPresentingThePicker() throws {
        let fixture = tempDir.appendingPathComponent("seed.vauchibackup")
        try Data("backup-bytes".utf8).write(to: fixture)
        AppViewModel.debugFilePickFixture = fixture

        viewModel.handleExchangeCommands([
            .filePickFromUser(acceptedMimeTypes: [], purpose: .importBackup),
        ])

        XCTAssertNil(viewModel.pendingFilePick, "the fixture stands in for the user's pick")
    }

    func testUnreadableFixtureFallsBackToThePicker() {
        AppViewModel.debugFilePickFixture = tempDir.appendingPathComponent("missing.vauchibackup")

        viewModel.handleExchangeCommands([
            .filePickFromUser(acceptedMimeTypes: [], purpose: .importBackup),
        ])

        XCTAssertEqual(viewModel.pendingFilePick?.purpose, .importBackup,
                       "a fixture that cannot be read must not swallow the pick")
    }
}
