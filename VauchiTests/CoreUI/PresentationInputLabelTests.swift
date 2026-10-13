// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// An `Input` node carries a label Core prepared ("Value", "Comment"). A
// plain SwiftUI TextField uses its title only as a placeholder, and the
// prompt replaces even that, so a field holding a value showed no label at
// all: Edit Field read "+44 20 7946 0958" with nothing saying what it was
// (vauchi/private#421). Android, macOS, GTK and Qt draw the label above
// the field.
//
// Traces to: features/generic_presentation_protocol.feature

import SwiftUI
@testable import Vauchi
import XCTest

final class PresentationInputLabelTests: XCTestCase {
    func testAFilledInFieldDrawsItsLabelAboveIt() throws {
        let labeled = try renderedHeight(of: inputNode(label: "Value"))
        let unlabeled = try renderedHeight(of: inputNode(label: ""))

        XCTAssertGreaterThan(labeled, unlabeled + 10)
    }

    private func inputNode(label: String) throws -> PresentationNode {
        let json = """
        {"Input": {
          "binding_id": "value",
          "label": "\(label)",
          "value": "+44 20 7946 0958",
          "placeholder": "Phone number",
          "input_kind": "text",
          "max_length": null,
          "validation_error": null,
          "enabled": true,
          "accessibility": {"label": "Value", "description": null}
        }}
        """
        return try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
    }

    private func renderedHeight(of node: PresentationNode) throws -> CGFloat {
        let controller = UIHostingController(rootView: InputHost(node: node))
        return controller.sizeThatFits(in: CGSize(width: 375, height: 2000)).height
    }
}

private struct InputHost: View {
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
