// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// App Store Connect rejected TestFlight build 0.1.13 (14) with ITMS-91056,
// "Invalid privacy manifest": the file opened with two licence comments
// before its <?xml declaration, which XML allows only at the very start.
// plutil accepts that; Apple's validator and strict XML parsers do not
// (vauchi/private#22). The licence lives in REUSE.toml instead.
//
// Reads the source file: it is what a developer edits, and Xcode copies it
// into the bundle byte for byte.

import XCTest

final class PrivacyManifestContractTests: XCTestCase {
    private func manifest() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Vauchi/PrivacyInfo.xcprivacy")
        return try Data(contentsOf: url)
    }

    func testTheManifestStartsWithItsXMLDeclaration() throws {
        let data = try manifest()

        XCTAssertTrue(
            data.starts(with: Data("<?xml".utf8)),
            "PrivacyInfo.xcprivacy must begin with <?xml; found: "
                + (String(bytes: data.prefix(40), encoding: .utf8) ?? "<not UTF-8>")
        )
    }

    func testAStrictXMLParserAcceptsTheManifest() throws {
        let parser = try XMLParser(data: manifest())

        XCTAssertTrue(parser.parse(), "XML error: \(String(describing: parser.parserError))")
    }

    func testTheManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let manifest = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: manifest(), format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }
}
