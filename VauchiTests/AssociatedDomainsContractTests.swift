// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Exchange links and QRs are https://vauchi.app/x#… (vauchi/private#277).
// With the app installed they open it as a Universal Link, which SwiftUI
// hands to the same `.onOpenURL` that forwards every URI to Core. The
// domain claim lives in the entitlements file; vauchi.app's
// apple-app-site-association limits it to /x.
//
// Reads the source entitlements file: a test bundle on the simulator is not
// signed with them, and the file is what a developer edits to break this.

import XCTest

final class AssociatedDomainsContractTests: XCTestCase {
    func testTheAppClaimsVauchiAppAsItsOnlyUniversalLinkDomain() throws {
        let entitlementsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Vauchi/Vauchi.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            entitlements["com.apple.developer.associated-domains"] as? [String],
            ["applinks:vauchi.app"]
        )
    }
}
