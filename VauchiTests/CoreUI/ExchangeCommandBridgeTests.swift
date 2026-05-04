// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ExchangeCommandBridgeTests.swift
// Verifies `AppViewModel.handleExchangeCommands` correctly translates
// each `ExchangeCommandDTO` variant into the matching @Published
// state that drives a SwiftUI presentation:
//
//   ExchangeCommand                    @Published state on AppViewModel
//   ─────────────────────────────────  ────────────────────────────────
//   filePickFromUser(mime, purpose) -> pendingFilePick: PendingFilePick?
//   imagePickFromLibrary            -> showImagePicker: Bool
//   imageCaptureFromCamera          -> showCameraPicker: Bool
//
// These are the three command-event bridges where SwiftUI presents
// a system-owned modal (UIDocumentPickerViewController, PHPicker,
// AVCapture). Verifying the *system modal actually appeared* via
// `XCUIApplication(bundleIdentifier: "com.apple.PhotosPicker"…)`
// or process-foreground polling is structurally racy and
// OS-version-coupled — the system picker covers any in-app
// sentinel before XCTest can query it. See CC-23.
//
// The contract worth verifying is that the bridge fires; SwiftUI's
// job to render the modal once the @Published state flips is
// well-trodden and OS-tested. Upstream (core engine emits the
// matching command on the matching action) is covered by
// `core/vauchi-app/tests/it/file_picker_wiring_tests.rs`.

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class ExchangeCommandBridgeTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Bridge Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - filePickFromUser

    /// Scenario: core emits `ExchangeCommand::FilePickFromUser` for
    /// `ImportContacts`. The bridge must store the purpose + accepted
    /// MIME types on `pendingFilePick`, which the
    /// `FilePickerModifier` then drives `.fileImporter` from.
    func testFilePickFromUserSetsPendingFilePick() {
        XCTAssertNil(viewModel.pendingFilePick, "pendingFilePick should start nil")

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
        XCTAssertEqual(pending.purpose, .importContacts)
        XCTAssertEqual(pending.acceptedMimeTypes, ["text/vcard", "text/x-vcard"])
    }

    /// `sendFilePickCancelled` clears pending state and emits the
    /// matching hardware event back to core. Covers the modifier's
    /// "user dismissed without our handler" cleanup path.
    func testSendFilePickCancelledClearsPendingState() {
        viewModel.handleExchangeCommands([
            .filePickFromUser(acceptedMimeTypes: ["text/vcard"], purpose: .importContacts),
        ])
        XCTAssertNotNil(viewModel.pendingFilePick, "precondition")

        viewModel.sendFilePickCancelled()

        XCTAssertNil(viewModel.pendingFilePick)
    }

    // MARK: - imagePickFromLibrary

    /// Scenario: core emits `ExchangeCommand::ImagePickFromLibrary`
    /// (e.g. for avatar set). Bridge flips `showImagePicker = true`,
    /// which `CoreScreenView` reads to present `ImagePickerSheet`
    /// (PHPickerViewController wrapper).
    func testImagePickFromLibrarySetsShowImagePicker() {
        XCTAssertFalse(viewModel.showImagePicker, "showImagePicker should start false")

        viewModel.handleExchangeCommands([.imagePickFromLibrary])

        XCTAssertTrue(
            viewModel.showImagePicker,
            "showImagePicker should flip true after ImagePickFromLibrary command"
        )
        XCTAssertFalse(
            viewModel.showCameraPicker,
            "ImagePickFromLibrary must not also flip the camera flag"
        )
    }

    // MARK: - imageCaptureFromCamera

    /// Scenario: core emits `ExchangeCommand::ImageCaptureFromCamera`
    /// (avatar capture). Bridge flips `showCameraPicker = true`,
    /// which `CoreScreenView` reads to present `AVCameraCaptureSheet`.
    func testImageCaptureFromCameraSetsShowCameraPicker() {
        XCTAssertFalse(viewModel.showCameraPicker, "showCameraPicker should start false")

        viewModel.handleExchangeCommands([.imageCaptureFromCamera])

        XCTAssertTrue(
            viewModel.showCameraPicker,
            "showCameraPicker should flip true after ImageCaptureFromCamera command"
        )
        XCTAssertFalse(
            viewModel.showImagePicker,
            "ImageCaptureFromCamera must not also flip the library flag"
        )
    }

    // MARK: - imagePickFromFile

    /// iOS uses the photo library instead of a file picker for
    /// images. The bridge must NOT set `pendingFilePick` for this
    /// command (which would surface a generic file importer); it
    /// silently emits the cancel hardware event so core's
    /// state machine doesn't block.
    func testImagePickFromFileDoesNotSetPendingFilePick() {
        viewModel.handleExchangeCommands([.imagePickFromFile])

        XCTAssertNil(
            viewModel.pendingFilePick,
            "ImagePickFromFile must not present a generic file picker on iOS"
        )
        XCTAssertFalse(
            viewModel.showImagePicker,
            "ImagePickFromFile must not implicitly open the photo library"
        )
        XCTAssertFalse(viewModel.showCameraPicker)
    }

    // MARK: - Multiple commands in one batch

    /// `handleExchangeCommands` accepts a Vec — the bridge must
    /// process each command in order without skipping.
    func testMultipleCommandsAllSetTheirState() {
        viewModel.handleExchangeCommands([
            .imagePickFromLibrary,
            .filePickFromUser(acceptedMimeTypes: [], purpose: .importContacts),
        ])

        XCTAssertTrue(viewModel.showImagePicker)
        XCTAssertNotNil(viewModel.pendingFilePick)
    }
}
