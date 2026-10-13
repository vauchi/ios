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
        _ = try state.apply(commands + ownSurfaceProfile())
        return state
    }

    /// The catalog carries no profile, so each shell renders it at its own
    /// size, and a sub-screen batch also replaces its parent. Core replaces
    /// the entry's own surface last; naming it here keeps the app's
    /// no-profile fallback, which live batches rely on, out of the catalog
    /// (vauchi/private#420).
    private func ownSurfaceProfile() -> [PresentationCommand] {
        let hasProfile = commands.contains { command in
            if case .setPresentationProfile = command {
                return true
            }
            return false
        }
        let own = commands.reversed().lazy.compactMap { command -> String? in
            if case let .replaceSurface(surface) = command {
                return surface.surfaceID
            }
            return nil
        }.first
        guard !hasProfile, let own else { return [] }
        return [.setPresentationProfile(PresentationProfile(
            windowClass: .compact,
            paneLayout: .single,
            primarySurface: own,
            detailSurface: nil,
            activeSurface: own
        ))]
    }
}
