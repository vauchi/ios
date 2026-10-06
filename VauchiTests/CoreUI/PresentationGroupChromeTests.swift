// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// A `Group` node with no label only lays its children out; a labeled one is
// a titled section. Every group used to draw as a `GroupBox`, so an
// unlabeled one still took the box's padding and an empty title slot.
// Hover's camera row nests two such groups: 92pt of padding that never gave
// way pushed the tab bar 61pt off an iPhone SE (rig, 2026-10-06,
// vauchi/private#534). Android already draws an unlabeled group as a bare
// column.

import SwiftUI
@testable import Vauchi
import XCTest

final class PresentationGroupChromeTests: XCTestCase {
    func testAnUnlabeledGroupAddsNoHeightAroundItsChildren() throws {
        let child = try renderedHeight(of: textNode())
        let group = try renderedHeight(of: groupNode(label: nil))

        XCTAssertEqual(group, child, accuracy: 0.5)
    }

    func testALabeledGroupStillDrawsAsATitledBox() throws {
        let child = try renderedHeight(of: textNode())
        let group = try renderedHeight(of: groupNode(label: "Contact info"))

        XCTAssertGreaterThan(group, child + 16)
    }

    func testOnlyALabeledGroupDrawsABox() {
        XCTAssertFalse(PresentationNodeView.groupDrawsBox(label: nil))
        XCTAssertFalse(PresentationNodeView.groupDrawsBox(label: ""))
        XCTAssertTrue(PresentationNodeView.groupDrawsBox(label: "Contact info"))
    }

    private let textJSON = """
    {"Text": {"id": "status", "content": "Looking for the other phone", "style": "body",
      "accessibility": {"label": "Looking for the other phone", "description": null}}}
    """

    private func textNode() throws -> PresentationNode {
        try JSONDecoder().decode(PresentationNode.self, from: Data(textJSON.utf8))
    }

    /// Anything taller than the lone child is the group's own chrome.
    private func groupNode(label: String?) throws -> PresentationNode {
        let encodedLabel = label.map { #""\#($0)""# } ?? "null"
        let json = """
        {"Group": {
          "id": "row",
          "label": \(encodedLabel),
          "axis": "horizontal",
          "children": [\(textJSON)],
          "accessibility": {"label": "row", "description": null}
        }}
        """
        return try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
    }

    private func renderedHeight(of node: PresentationNode) throws -> CGFloat {
        let controller = UIHostingController(rootView: GroupHost(node: node))
        return controller.sizeThatFits(in: CGSize(width: 375, height: 2000)).height
    }
}

private struct GroupHost: View {
    let node: PresentationNode
    @FocusState private var focused: String?

    var body: some View {
        PresentationNodeView(
            node: node,
            surfaceID: "surface",
            minimumTarget: 44,
            useFrontCamera: false,
            onCameraPermissionDenied: {},
            focusedBinding: $focused,
            onEvent: { _ in }
        )
        .frame(width: 375)
    }
}
