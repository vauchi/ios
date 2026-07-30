// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

final class PresentationStateTests: XCTestCase {
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
        XCTAssertEqual(state.overlay?.overlay.kind, .navigation)

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
        XCTAssertEqual(state.overlay?.overlay.kind, .actionMenu)
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

    private func jsonObject(_ value: some Encodable) throws -> NSDictionary {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? NSDictionary
        )
    }

    private func surfaceJSON(
        revision: Int,
        nodes: String = "[]"
    ) -> String {
        """
        {
          "surface_id":"main",
          "revision":\(revision),
          "title":"Prepared by Core",
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
