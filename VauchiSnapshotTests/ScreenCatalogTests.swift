// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Core's screen catalog (`vauchi-app/fixtures/screen_catalog_v1.json`)
/// is a list of command batches in the same shape as the contract
/// fixture's `initial_commands`; each entry reduces to one screen.
final class ScreenCatalogTests: XCTestCase {
    func testTwoEntryCatalogReducesIntoTwoSurfaces() throws {
        let catalog = try JSONDecoder().decode(
            ScreenCatalog.self,
            from: Data(ScreenCatalogFixture.twoEntries.utf8)
        )

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.screens.map(\.codeID), ["onboarding", "contacts"])
        XCTAssertEqual(catalog.screens.map(\.title), ["Welcome", "Contacts"])
        XCTAssertEqual(catalog.screens.map(\.locale), ["en", "en"])

        let states = try catalog.screens.map { try $0.reduce() }
        XCTAssertEqual(states.map(\.activeSurfaceID), ["onboarding", "contacts"])
        XCTAssertEqual(
            states.map { $0.surfaces[$0.activeSurfaceID ?? ""]?.title },
            ["Welcome to Vauchi", "Contacts"]
        )
        XCTAssertEqual(states[0].activeBar?.primary?.label, "Create new identity")
        XCTAssertEqual(states[1].activeNavigation?.navigation.items.count, 2)
        XCTAssertEqual(states[1].activeNavigation?.navigation.items.last?.selected, true)
    }

    func testEntryWithoutSurfaceFailsToReduce() throws {
        let catalog = try JSONDecoder().decode(
            ScreenCatalog.self,
            from: Data(ScreenCatalogFixture.barOnly.utf8)
        )

        XCTAssertThrowsError(try catalog.screens[0].reduce())
    }

    func testUnknownEnumValuesFallBackInsteadOfAbortingTheBatch() throws {
        let catalog = try JSONDecoder().decode(
            ScreenCatalog.self,
            from: Data(ScreenCatalogFixture.newerCoreValues.utf8)
        )

        let state = try catalog.screens[0].reduce()
        let surface = try XCTUnwrap(state.surfaces["future"])
        XCTAssertEqual(surface.layout, .scroll)
        guard case let .text(text) = surface.nodes[0] else {
            return XCTFail("expected a text node, got \(surface.nodes[0])")
        }
        XCTAssertEqual(text.style, .body)
        guard case let .text(placeholder) = surface.nodes[1] else {
            return XCTFail("expected a placeholder text node, got \(surface.nodes[1])")
        }
        XCTAssertTrue(placeholder.content.contains("Hologram"))
        XCTAssertEqual(state.activeBar?.primary?.tone, .standard)
        XCTAssertNil(state.activeBar?.primary?.shortcut)
    }
}

enum ScreenCatalogFixture {
    private static let tokens = """
    {"spacing_small":8,"spacing_medium":16,"spacing_large":24,"corner_radius":12,"minimum_target_size":48}
    """

    private static func action(_ id: String, _ label: String) -> String {
        """
        {"interaction_id":"\(id)","label":"\(label)","accessibility_label":"\(label)",\
        "icon_token":null,"enabled":true,"shortcut":null}
        """
    }

    private static func navigationItem(_ label: String, selected: Bool) -> String {
        """
        {"interaction_id":"nav.\(label)","label":"\(label)","accessibility_label":"\(label)",\
        "icon_token":"person","selected":\(selected),"badge_count":0}
        """
    }

    /// Trimmed from `presentation_contract_v1.json`'s `initial_commands`
    /// and its first step: the same command shapes, fewer nodes.
    static let twoEntries = """
    {"schema_version":1,"screens":[
      {"code_id":"onboarding","title":"Welcome","locale":"en","commands":[
        {"ReplaceSurface":{"surface":{"surface_id":"onboarding","revision":1,
          "title":"Welcome to Vauchi","subtitle":"Privacy-focused contact cards.",
          "accessibility_label":"Welcome to Vauchi","layout":"scroll","tokens":\(tokens),
          "nodes":[{"Status":{"id":null,"title":"Private by design","detail":"Encrypted.",
            "icon_token":"lock","badge":null,"tone":"neutral","activation":null,
            "accessibility":{"label":"Private by design","description":null}}}]}}},
        {"SetContextBar":{"surface_id":"onboarding","revision":1,"bar":{"back":null,
          "navigation":\(action("nav", "More")),
          "primary":\(action("create", "Create new identity")),
          "secondary":null}}},
        {"SetNavigation":{"surface_id":"onboarding","revision":1,"navigation":{"items":[
          \(navigationItem("Welcome", selected: true))]}}}
      ]},
      {"code_id":"contacts","title":"Contacts","locale":"en","commands":[
        {"ReplaceSurface":{"surface":{"surface_id":"contacts","revision":4,
          "title":"Contacts","subtitle":null,"accessibility_label":"Contacts",
          "layout":"scroll","tokens":\(tokens),
          "nodes":[{"Text":{"id":null,"content":"No contacts yet","style":"muted",
            "accessibility":{"label":"No contacts yet","description":null}}}]}}},
        {"SetContextBar":{"surface_id":"contacts","revision":4,"bar":{"back":null,
          "navigation":null,"primary":\(action("add", "Add")),"secondary":null}}},
        {"SetNavigation":{"surface_id":"contacts","revision":4,"navigation":{"items":[
          \(navigationItem("Card", selected: false)),
          \(navigationItem("Contacts", selected: true))]}}}
      ]}
    ]}
    """

    static let barOnly = """
    {"schema_version":1,"screens":[
      {"code_id":"orphan","title":"Orphan","locale":"en","commands":[
        {"SetContextBar":{"surface_id":"orphan","revision":1,"bar":{"back":null,
          "navigation":null,"primary":null,"secondary":null}}}
      ]}
    ]}
    """

    /// Values a newer Core may emit that this shell does not know.
    static let newerCoreValues = """
    {"schema_version":1,"screens":[
      {"code_id":"future","title":"Future","locale":"en","commands":[
        {"ReplaceSurface":{"surface":{"surface_id":"future","revision":1,
          "title":"Future","subtitle":null,"accessibility_label":"Future",
          "layout":"floating","tokens":\(tokens),
          "nodes":[
            {"Text":{"id":null,"content":"Hi","style":"display",
              "accessibility":{"label":"Hi","description":null}}},
            {"Hologram":{"id":"h1","depth":3}}
          ]}}},
        {"SetContextBar":{"surface_id":"future","revision":1,"bar":{"back":null,
          "navigation":null,
          "primary":{"interaction_id":"go","label":"Go","accessibility_label":"Go",
            "icon_token":null,"enabled":true,"shortcut":"teleport","tone":"celebratory"},
          "secondary":null}}}
      ]}
    ]}
    """
}
