// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// RG-11: core!1582 adds `accepted_extensions` (lowercase, dot-less)
// to `Command::FilePickFromUser` beside `accepted_mime_types`, but
// the pinned vauchi-platform-swift build's `CommandDTO.filePickFromUser`
// predates the field, so it can't be read off the decoded DTO.
// `AppViewModel.acceptedExtensionsByCommandIndex` re-reads the raw
// "commands" JSON to recover it; `FilePickerModifier
// .contentTypes(forAcceptedExtensions:)` maps the result to `UTType`s.
// These two pure functions are the whole RG-11 contract; wiring them
// into `pendingFilePick` is covered by `ExchangeCommandBridgeTests`.

import UniformTypeIdentifiers
@testable import Vauchi
import XCTest

@MainActor
final class FilePickerAcceptedExtensionsTests: XCTestCase {
    // MARK: - FilePickerModifier.contentTypes(forAcceptedExtensions:)

    func testContentTypesMapsExtensionsToMatchingUTTypes() {
        let types = FilePickerModifier.contentTypes(forAcceptedExtensions: ["vcf"])

        XCTAssertEqual(types, [.vCard])
    }

    func testContentTypesFallsBackToDataWhenExtensionsEmpty() {
        let types = FilePickerModifier.contentTypes(forAcceptedExtensions: [])

        XCTAssertEqual(types, [.data])
    }

    // MARK: - AppViewModel.acceptedExtensionsByCommandIndex(fromCommandsJSON:)

    func testAcceptedExtensionsByCommandIndexDecodesPresentField() {
        let json = """
        {"commands": [
            {"FilePickFromUser": {
                "accepted_mime_types": ["text/vcard"],
                "accepted_extensions": ["vcf", "vcard"],
                "purpose": "ImportContacts"
            }}
        ]}
        """
        let extensions = AppViewModel.acceptedExtensionsByCommandIndex(
            fromCommandsJSON: Data(json.utf8)
        )

        XCTAssertEqual(extensions, [["vcf", "vcard"]])
    }

    func testAcceptedExtensionsByCommandIndexDecodesAbsentFieldAsEmpty() {
        let json = """
        {"commands": [
            {"FilePickFromUser": {
                "accepted_mime_types": ["text/vcard"],
                "purpose": "ImportContacts"
            }}
        ]}
        """
        let extensions = AppViewModel.acceptedExtensionsByCommandIndex(
            fromCommandsJSON: Data(json.utf8)
        )

        XCTAssertEqual(extensions, [[]], "pinned 0.64.0 core omits accepted_extensions entirely")
    }

    func testAcceptedExtensionsByCommandIndexAlignsByIndexAcrossMixedCommands() {
        let json = """
        {"commands": [
            "ImagePickFromLibrary",
            {"FilePickFromUser": {
                "accepted_mime_types": [],
                "accepted_extensions": ["vauchi"],
                "purpose": "ImportBackup"
            }}
        ]}
        """
        let extensions = AppViewModel.acceptedExtensionsByCommandIndex(
            fromCommandsJSON: Data(json.utf8)
        )

        XCTAssertEqual(extensions, [[], ["vauchi"]])
    }
}
