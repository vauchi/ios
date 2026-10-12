// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// TestFlight rejects an upload whose build number it has seen before, and
// auto-tag names each release from MARKETING_VERSION. The app must therefore
// ship the version and build number project.yml sets, not fixed literals in
// Info.plist (vauchi/private#665). Before this, every build said 1.0.0 (1).

import XCTest

final class BundleVersionContractTests: XCTestCase {
    func testTheAppShipsTheVersionAndBuildNumberProjectYmlSets() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            try buildSetting("MARKETING_VERSION", in: project)
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            try buildSetting("CURRENT_PROJECT_VERSION", in: project)
        )
    }

    private func buildSetting(_ name: String, in project: String) throws -> String {
        let line = try XCTUnwrap(
            project.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(name):") },
            "project.yml sets no \(name)"
        )
        return line.split(separator: ":", maxSplits: 1)[1]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
