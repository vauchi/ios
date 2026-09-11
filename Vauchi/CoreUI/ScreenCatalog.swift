// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Core's screen catalog fixture (`vauchi-app/fixtures/screen_catalog_v1.json`):
/// every app screen as the command batch Core emits for it, so a shell can
/// replay each one through its real renderer without driving the app.
struct ScreenCatalog: Decodable {
    let schemaVersion: Int
    let screens: [ScreenCatalogEntry]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case screens
    }

    static func load(from url: URL) throws -> ScreenCatalog {
        try JSONDecoder().decode(ScreenCatalog.self, from: Data(contentsOf: url))
    }
}

struct ScreenCatalogEntry: Decodable {
    let codeID: String
    let title: String
    let locale: String
    let commands: [PresentationCommand]

    private enum CodingKeys: String, CodingKey {
        case codeID = "code_id"
        case title
        case locale
        case commands
    }

    /// The state the app would hold after Core sent this batch, produced by
    /// the reducer the app itself uses.
    func reduce() throws -> PresentationState {
        var state = PresentationState()
        _ = try state.apply(commands)
        return state
    }
}
