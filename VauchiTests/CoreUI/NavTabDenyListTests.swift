// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// NavTabDenyListTests.swift
// Frontend-source deny-list for the zero-domain-vocab tab migration —
// the iOS analogue of core's `wire_humble_keys_tests.rs` (ADR-043 Am4,
// tier0-d plan item 2 §4 "Enforcement").
//
// After the data-driven tab bar landed, the five top-level tabs are
// navigated by the opaque `action_id` core hands out via `tabInfo()`
// (forwarded as `UserAction::NavigateToTab`). The frontend must never
// reconstruct the domain *variant* name to drive that navigation —
// doing so silently re-domains the renderer under the next refactor
// (the exact failure Wire Humble was written to prevent).
//
// This test fails if any production source navigates to a migrated tab
// by its serde variant, via either dispatch style:
//   * navigateTo(screenJson: "\"Groups\"")   (escaped serde form)
//   * CoreScreenView(screenName: "Groups")   (legacy screenName init)
//
// Scope: only the three variants whose tab bodies are now fully
// action_id-driven (MyInfo, Contacts, Groups). "Exchange" and "More"
// stay allowed — they back native composite tabs / sub-screen flows
// that still legitimately navigate by variant pending the later
// navigate_to_json retirement tier.

import XCTest

final class NavTabDenyListTests: XCTestCase {
    /// Variant names that must not appear as navigation literals in
    /// production code anymore — they are tab-navigated by `action_id`.
    private static let forbiddenVariants = ["MyInfo", "Contacts", "Groups"]

    /// Root of the production sources: `<repo>/ios/Vauchi`.
    private static let productionSourceRoot: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreUI/
        .deletingLastPathComponent() // VauchiTests/
        .deletingLastPathComponent() // ios/
        .appendingPathComponent("Vauchi")
        .standardized

    func testNoProductionSourceNavigatesTabsByDomainVariant() throws {
        let fm = FileManager.default
        let root = Self.productionSourceRoot
        var isDir: ObjCBool = false
        XCTAssertTrue(
            fm.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue,
            "Production source root not found at \(root.path) — adjust the #filePath walk-up if the layout moved"
        )

        let enumerator = try XCTUnwrap(
            fm.enumerator(at: root, includingPropertiesForKeys: nil),
            "Could not enumerate \(root.path)"
        )

        var violations: [String] = []
        var scannedFileCount = 0

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            scannedFileCount += 1
            for variant in Self.forbiddenVariants {
                // Escaped serde form inside a Swift string: \"Groups\"
                let serdeNeedle = "\\\"\(variant)\\\""
                // Legacy CoreScreenView(screenName:) form: screenName: "Groups"
                let screenNameNeedle = "screenName: \"\(variant)\""
                for (label, needle) in [("screenJson serde", serdeNeedle), ("screenName init", screenNameNeedle)]
                    where contents.contains(needle) {
                    violations.append("\(fileURL.lastPathComponent): \(label) literal for \"\(variant)\"")
                }
            }
        }

        XCTAssertGreaterThan(scannedFileCount, 0, "Scanned no Swift files — the source walk is broken")
        XCTAssertTrue(
            violations.isEmpty,
            "Tabs must be navigated by the opaque action_id from tabInfo(), not the "
                + "domain variant. Re-domaining found:\n" + violations.joined(separator: "\n")
        )
    }
}
