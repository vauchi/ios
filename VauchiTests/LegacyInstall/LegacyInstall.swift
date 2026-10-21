// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

/// The installs from before vauchi/private#580 that Core's
/// `legacy_install_fixture` example writes, under `storageKey`. They are
/// checked in because the binding no longer has the constructor that wrote a
/// database under the shell's own key.
enum LegacyInstall: String {
    /// Identity "Before" and one imported contact, Carol.
    case before = "legacy-before"

    static let storageKey = Data(repeating: 0x58, count: 32)

    func copy(into dataDir: URL) throws {
        let source = try XCTUnwrap(Bundle(for: BundleMarker.self).url(forResource: rawValue, withExtension: "db"))
        try FileManager.default.copyItem(at: source, to: dataDir.appendingPathComponent("vauchi.db"))
    }
}

private final class BundleMarker {}
