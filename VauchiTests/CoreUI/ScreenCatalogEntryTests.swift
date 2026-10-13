// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core's screen catalog carries no layout profile, so each shell renders it
// at its own size. A sub-screen entry also replaces its parent, and with no
// profile the app takes the alphabetically first surface, so the catalog
// drew Settings for Settings > Advanced (vauchi/private#420). Core
// guarantees the entry's own surface is replaced last; the catalog, not
// the app, uses that, because live batches make no such promise.
//
// Traces to: features/generic_presentation_protocol.feature

@testable import Vauchi
import XCTest

final class ScreenCatalogEntryTests: XCTestCase {
    func testASubScreenEntryShowsItsOwnSurface() throws {
        let entry = try JSONDecoder().decode(ScreenCatalogEntry.self, from: Data("""
        {"code_id":"settings_advanced","title":"Advanced","locale":"en","commands":[
          {"ReplaceSurface":{"surface":\(surface("settings"))}},
          {"ReplaceSurface":{"surface":\(surface("settings_advanced"))}}
        ]}
        """.utf8))

        let state = try entry.reduce()

        XCTAssertEqual(state.activeSurfaceID, "settings_advanced")
        XCTAssertEqual(state.visibleSurfaceIDs, ["settings_advanced"])
    }

    private func surface(_ id: String) -> String {
        """
        {"surface_id":"\(id)","revision":1,"title":"\(id)","subtitle":null,
         "accessibility_label":"\(id)","layout":"scroll",
         "tokens":{"spacing_small":4,"spacing_medium":8,"spacing_large":16,
                   "corner_radius":8,"minimum_target_size":44},
         "nodes":[]}
        """
    }
}
