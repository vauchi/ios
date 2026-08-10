// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import VauchiPlatform
import XCTest

final class PresentationStateTests: XCTestCase {
    // @scenario: generic_presentation_protocol.feature :: Every shell renders the same prepared presentation
    func testSharedPresentationContractReachesExpectedState() throws {
        let fixture = try JSONDecoder().decode(
            SharedPresentationContract.self,
            from: Data(presentationContractFixtureJson().utf8)
        )
        XCTAssertEqual(fixture.schemaVersion, 1)

        var state = PresentationState()
        XCTAssertTrue(try state.apply(fixture.initialCommands).isEmpty)
        for step in fixture.steps {
            XCTAssertTrue(try state.apply(step.commands).isEmpty)
        }

        XCTAssertEqual(state.activeSurfaceID, fixture.expectedState.activeSurfaceID)
        XCTAssertEqual(
            state.surfaces[fixture.expectedState.activeSurfaceID],
            fixture.expectedState.surface
        )
        XCTAssertEqual(
            state.bars[fixture.expectedState.activeSurfaceID]?.bar,
            fixture.expectedState.contextBar
        )
    }

    func testAppliesPreparedTransactionAtomically() throws {
        let commands = try decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"SetContextBar":{
            "surface_id":"main",
            "revision":1,
            "bar":{
              "back":null,
              "navigation":null,
              "primary":\(actionJSON(id: "save", label: "Save")),
              "secondary":null
            }
          }},
          {"SetPresentationProfile":{"profile":{
            "window_class":"compact",
            "pane_layout":"single",
            "primary_surface":"main",
            "detail_surface":null,
            "active_surface":"main"
          }}}
        ]}
        """)

        var state = PresentationState()
        let effects = try state.apply(commands)

        XCTAssertEqual(state.surfaces["main"]?.revision, 1)
        XCTAssertEqual(state.bars["main"]?.bar.primary?.label, "Save")
        XCTAssertEqual(state.profile?.activeSurface, "main")
        XCTAssertTrue(effects.isEmpty)
    }

    func testRejectsWholeStaleTransaction() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 2))}}
        ]}
        """))

        XCTAssertThrowsError(try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"SetContextBar":{
            "surface_id":"main",
            "revision":1,
            "bar":{
              "back":null,
              "navigation":null,
              "primary":\(actionJSON(id: "stale", label: "Stale")),
              "secondary":null
            }
          }}
        ]}
        """)))
        XCTAssertEqual(state.surfaces["main"]?.revision, 2)
        XCTAssertNil(state.bars["main"])
    }

    /// Core's surface revision advances only on user actions, so racing
    /// full rebuilds (wakeup re-load, invalidation dispatch, identity
    /// seeding) legitimately re-emit the same surface at the same
    /// revision — sometimes with newer content at that revision. Only a
    /// strictly older revision is stale; equal must re-apply, last-writer
    /// wins, or a benign duplicate rebuild surfaces as a user-facing
    /// "Presentation error" alert.
    func testAppliesSameRevisionRebuildLastWriterWins() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1, title: "Old"))}}
        ]}
        """))

        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1, title: "New"))}}
        ]}
        """))

        XCTAssertEqual(state.surfaces["main"]?.title, "New")
    }

    func testReplacementClearsOldChrome() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"SetContextBar":{
            "surface_id":"main",
            "revision":1,
            "bar":{
              "back":null,
              "navigation":null,
              "primary":\(actionJSON(id: "save", label: "Save")),
              "secondary":null
            }
          }}
        ]}
        """))

        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 2))}}
        ]}
        """))

        XCTAssertNil(state.bars["main"])
    }

    func testPreservesDistinctOverlayKinds() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"PresentOverlay":{
            "surface_id":"main",
            "revision":1,
            "overlay":{
              "kind":"navigation",
              "title":"Navigate",
              "items":[\(actionJSON(id: "contacts", label: "Contacts"))]
            }
          }}
        ]}
        """))
        XCTAssertEqual(state.activeOverlay?.overlay.kind, .navigation)

        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"PresentOverlay":{
            "surface_id":"main",
            "revision":1,
            "overlay":{
              "kind":"action_menu",
              "title":"More",
              "items":[\(actionJSON(id: "archive", label: "Archive"))]
            }
          }}
        ]}
        """))
        XCTAssertEqual(state.activeOverlay?.overlay.kind, .actionMenu)
    }

    /// Core makes the context-bar menu buttons toggle by rewriting a repeat
    /// `PresentOverlay` into `DismissOverlay`. Without a case for it the
    /// command decodes to nothing useful and the menu never closes — the same
    /// gap fixed on Android in `vauchi/android!621`.
    func testDismissOverlayClosesTheOpenOverlay() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"PresentOverlay":{
            "surface_id":"main",
            "revision":1,
            "overlay":{"kind":"navigation","title":"More","items":[]}
          }}
        ]}
        """))
        XCTAssertEqual(state.activeOverlay?.overlay.kind, .navigation)

        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"DismissOverlay":{
            "surface_id":"main",
            "revision":1,
            "kind":"navigation"
          }}
        ]}
        """))
        XCTAssertNil(
            state.activeOverlay,
            "a dismissed overlay must leave no overlay state"
        )
    }

    /// Picking an item in the menu navigates, but Core sends no dismissal: it
    /// clears its own open-overlay state each dispatch and expects the overlay
    /// to die with the surface it was raised over.
    ///
    /// Rendering it unscoped left the menu drawn *over* the destination on an
    /// iPhone SE, so the rows underneath could not be tapped at all, and the
    /// next menu tap re-presented it because Core believed nothing was open
    /// (`2026-08-07-ios-stale-overlay-and-raw-error-alert`).
    func testOverlayDoesNotOutliveTheSurfaceThatOwnsIt() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"PresentOverlay":{
            "surface_id":"main",
            "revision":1,
            "overlay":{"kind":"navigation","title":"More","items":[]}
          }}
        ]}
        """))
        XCTAssertEqual(state.activeOverlay?.overlay.kind, .navigation)

        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 2))}}
        ]}
        """))
        XCTAssertNil(
            state.activeOverlay,
            "an overlay bound to an older surface revision must stop rendering"
        )
    }

    /// Choosing a destination navigates to a *different* surface id, and Core
    /// sends no dismissal for the surface left behind — it clears its own
    /// open-overlay state and expects the shell to scope the overlay to the
    /// surface it was raised over.
    ///
    /// Holding one unscoped overlay field could not express that, so the menu
    /// stayed drawn over the destination and the next destination tap
    /// dispatched against a surface Core no longer considered active. Core
    /// fail-closed rejects that, and the shell showed the rejection as a
    /// "Presentation error" alert: 55 of them in a single test:ui run
    /// (job 15799876791), which is what finally reproduced
    /// `2026-08-07-ios-stale-overlay-and-raw-error-alert` outside a device.
    ///
    /// A broader "any ReplaceSurface clears the overlay" rule was tried for
    /// this and reverted (vauchi/ios!630) because it also killed an overlay
    /// raised earlier in the same transaction. Keying overlays by surface —
    /// the shape `bars` already has — fixes the gap without that ordering
    /// assumption.
    func testOverlayStopsRenderingOnceAnotherSurfaceIsActive() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"SetPresentationProfile":{"profile":{
            "window_class":"compact",
            "pane_layout":"single",
            "primary_surface":"main",
            "detail_surface":null,
            "active_surface":"main"
          }}},
          {"PresentOverlay":{
            "surface_id":"main",
            "revision":1,
            "overlay":{"kind":"navigation","title":"More","items":[]}
          }}
        ]}
        """))
        XCTAssertEqual(state.activeOverlay?.overlay.kind, .navigation)

        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1, surfaceID: "exchange"))}},
          {"SetPresentationProfile":{"profile":{
            "window_class":"compact",
            "pane_layout":"single",
            "primary_surface":"exchange",
            "detail_surface":null,
            "active_surface":"exchange"
          }}}
        ]}
        """))
        XCTAssertNil(
            state.activeOverlay,
            "a menu raised over 'main' must not stay drawn over 'exchange'"
        )
    }

    /// The overlay raised over one surface must not leak into another that
    /// happens to become active — scoping is per surface, not "most recent".
    func testOverlayIsScopedToTheSurfaceItWasRaisedOver() throws {
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1))}},
          {"ReplaceSurface":{"surface":\(surfaceJSON(revision: 1, surfaceID: "exchange"))}},
          {"SetPresentationProfile":{"profile":{
            "window_class":"compact",
            "pane_layout":"single",
            "primary_surface":"exchange",
            "detail_surface":null,
            "active_surface":"exchange"
          }}},
          {"PresentOverlay":{
            "surface_id":"main",
            "revision":1,
            "overlay":{"kind":"navigation","title":"More","items":[]}
          }}
        ]}
        """))

        XCTAssertNil(
            state.activeOverlay,
            "an overlay raised over 'main' must not render while 'exchange' is active"
        )
    }

    func testEventEncoderPreservesOpaqueIdentifiersAndRawEnvironment() throws {
        let activation = PresentationEvent.actionActivated(
            surfaceID: "detail",
            interactionID: "opaque/action"
        )
        XCTAssertEqual(
            try jsonObject(activation),
            [
                "ActionActivated": [
                    "surface_id": "detail",
                    "interaction_id": "opaque/action",
                ],
            ] as NSDictionary
        )

        let environment = PresentationEvent.environmentChanged(
            availableWidth: 600,
            availableHeight: 900,
            inputModes: [.touch, .keyboard],
            motion: .reduced
        )
        XCTAssertEqual(
            try jsonObject(environment),
            [
                "PresentationEnvironmentChanged": [
                    "available_width": 600,
                    "available_height": 900,
                    "input_modes": ["touch", "keyboard"],
                    "motion": "reduced",
                ],
            ] as NSDictionary
        )

        XCTAssertEqual(
            try jsonObject(PresentationEvent.deepLinkOpened(uri: "vauchi://opaque")),
            ["DeepLinkOpened": ["uri": "vauchi://opaque"]] as NSDictionary
        )
        XCTAssertEqual(
            try JSONEncoder().encode(PresentationEvent.appBackgrounded),
            Data(#""AppBackgrounded""#.utf8)
        )
        XCTAssertEqual(
            try JSONEncoder().encode(PresentationEvent.presentationInvalidated),
            Data(#""PresentationInvalidated""#.utf8)
        )
    }

    func testNodeIdentityKeepsBindingAndFocusStableAcrossLayoutChanges() throws {
        let node = try JSONDecoder().decode(
            PresentationNode.self,
            from: Data("""
            {"Input":{
              "binding_id":"display_name",
              "label":"Display name",
              "value":"Alice",
              "placeholder":null,
              "input_kind":"text",
              "max_length":80,
              "validation_error":null,
              "enabled":true,
              "accessibility":{"label":"Display name","description":null}
            }}
            """.utf8)
        )

        XCTAssertEqual(node.identityID, "binding:display_name")
        XCTAssertEqual(node.focusIdentity, "display_name")
    }

    func testResponsiveProfilePreservesPreparedSelectionAndCausalUndo() throws {
        let selectedNodes = #"""
        [{"Choice":{
          "binding_id":"trust",
          "label":"Trust",
          "selected":"verified",
          "options":[{"id":"verified","label":"Verified"}],
          "enabled":true,
          "accessibility":{"label":"Trust","description":null}
        }}]
        """#
        var state = PresentationState()
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"ReplaceSurface":{"surface":\(surfaceJSON(
              revision: 4,
              nodes: selectedNodes
          ))}},
          {"SetContextBar":{
            "surface_id":"main",
            "revision":4,
            "bar":{
              "back":null,
              "navigation":null,
              "primary":\(actionJSON(
                  id: "undo.archive",
                  label: "Undo archive",
                  shortcut: "undo"
              )),
              "secondary":null
            }
          }},
          {"SetPresentationProfile":{"profile":{
            "window_class":"compact",
            "pane_layout":"single",
            "primary_surface":"main",
            "detail_surface":null,
            "active_surface":"main"
          }}}
        ]}
        """))
        _ = try state.apply(decodeCommands("""
        {"commands":[
          {"SetPresentationProfile":{"profile":{
            "window_class":"expanded",
            "pane_layout":"single",
            "primary_surface":"main",
            "detail_surface":null,
            "active_surface":"main"
          }}}
        ]}
        """))

        XCTAssertEqual(state.activeSurfaceID, "main")
        XCTAssertEqual(state.surfaces["main"]?.nodes.first?.identityID, "binding:trust")
        XCTAssertEqual(state.bars["main"]?.bar.primary?.shortcut, .undo)
    }

    private func decodeCommands(_ json: String) throws -> [PresentationCommand] {
        try JSONDecoder().decode(
            PresentationCommandEnvelope.self,
            from: Data(json.utf8)
        ).commands
    }

    private struct SharedPresentationContract: Decodable {
        let schemaVersion: Int
        let initialCommands: [PresentationCommand]
        let steps: [Step]
        let expectedState: ExpectedState

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case initialCommands = "initial_commands"
            case steps
            case expectedState = "expected_state"
        }

        struct Step: Decodable {
            let commands: [PresentationCommand]
        }

        struct ExpectedState: Decodable {
            let activeSurfaceID: String
            let surface: PresentationSurface
            let contextBar: PresentationContextBar

            enum CodingKeys: String, CodingKey {
                case activeSurfaceID = "active_surface_id"
                case surface
                case contextBar = "context_bar"
            }
        }
    }

    private func jsonObject(_ value: some Encodable) throws -> NSDictionary {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? NSDictionary
        )
    }

    private func surfaceJSON(
        revision: Int,
        surfaceID: String = "main",
        title: String = "Prepared by Core",
        nodes: String = "[]"
    ) -> String {
        """
        {
          "surface_id":"\(surfaceID)",
          "revision":\(revision),
          "title":"\(title)",
          "subtitle":null,
          "accessibility_label":"Prepared by Core",
          "layout":"scroll",
          "tokens":{
            "spacing_small":4,
            "spacing_medium":8,
            "spacing_large":16,
            "corner_radius":8,
            "minimum_target_size":44
          },
          "nodes":\(nodes)
        }
        """
    }

    private func actionJSON(
        id: String,
        label: String,
        shortcut: String? = nil
    ) -> String {
        """
        {
          "interaction_id":"\(id)",
          "label":"\(label)",
          "accessibility_label":"\(label)",
          "icon_token":null,
          "enabled":true,
          "shortcut":\(shortcut.map { "\"\($0)\"" } ?? "null")
        }
        """
    }
}
