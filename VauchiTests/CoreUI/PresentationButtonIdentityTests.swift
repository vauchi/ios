// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

/// Hover replaces its surface every ~100 ms, and Core mints each button's
/// interaction id per revision. Keyed by that id, SwiftUI rebuilt Cancel
/// mid-tap and the tap was lost (vauchi/private#532). A button list keeps
/// its buttons' identity across revisions; the tap then sends the latest
/// interaction.
///
/// Traces to: features/generic_presentation_protocol.feature
final class PresentationButtonIdentityTests: XCTestCase {
    private let hoverActions = #"""
    {
      "id": "exchange_actions",
      "label": null,
      "rows": [
        {
          "title": "Use Rear Camera",
          "subtitle": null,
          "detail": null,
          "icon_token": null,
          "image_data": null,
          "fallback_text": null,
          "selected": false,
          "enabled": true,
          "activation": {
            "interaction_id": "surface.1.interaction.0",
            "label": "Use Rear Camera",
            "accessibility_label": "Use Rear Camera",
            "icon_token": null,
            "enabled": true,
            "shortcut": null
          },
          "secondary_actions": [],
          "controls": [],
          "accessibility": {
            "label": "Use Rear Camera",
            "description": null
          }
        },
        {
          "title": "Cancel",
          "subtitle": null,
          "detail": null,
          "icon_token": null,
          "image_data": null,
          "fallback_text": null,
          "selected": false,
          "enabled": true,
          "activation": {
            "interaction_id": "surface.1.interaction.1",
            "label": "Cancel",
            "accessibility_label": "Cancel",
            "icon_token": null,
            "enabled": true,
            "shortcut": null
          },
          "secondary_actions": [],
          "controls": [],
          "accessibility": {
            "label": "Cancel",
            "description": null
          }
        }
      ],
      "searchable": false,
      "paging": null,
      "accessibility": {
        "label": "",
        "description": null
      },
      "style": "buttons"
    }
    """#

    private func decode(revision: Int) throws -> PresentationNode.ListNode {
        let json = hoverActions.replacingOccurrences(of: "surface.1.", with: "surface.\(revision).")
        return try JSONDecoder().decode(PresentationNode.ListNode.self, from: Data(json.utf8))
    }

    func testAButtonKeepsItsIdentityWhenTheSurfaceIsReplaced() throws {
        let before = try decode(revision: 1)
        let after = try decode(revision: 2)

        XCTAssertNotEqual(before.rows.map(\.id), after.rows.map(\.id), "precondition: ids are per revision")
        XCTAssertEqual(buttonKeys(before.rows), buttonKeys(after.rows))
        XCTAssertEqual(buttonKeys(after.rows).count, 2)
    }
}
