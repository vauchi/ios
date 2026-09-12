// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// A `Choice` node is Core's one-of-N selector. The design canvas draws a
// short choice (Perspective "Their Info / My Info for Them", Groups
// "Members / Visibility") as a segmented control and a long one (Settings
// Theme, 15 entries) as a menu, so the style follows the option count.
//
// Core rejects `Choice(None)` with `ValueTypeMismatch`, so the picker
// must offer only Core's own options: an extra "no selection" row would
// let the user pick a value the engine refuses.
//
// Traces to: features/contact_detail.feature, features/groups.feature

import SwiftUI
@testable import Vauchi
import XCTest

final class PresentationChoiceStyleTests: XCTestCase {
    func testTwoOptionsRenderAsASegmentedControl() throws {
        let control = try XCTUnwrap(
            renderedSegmentedControl(for: choiceNode(options: ["Their Info", "My Info for Them"])),
            "a two-way choice must render as a segmented control"
        )

        XCTAssertEqual(control.numberOfSegments, 2)
        XCTAssertEqual(control.titleForSegment(at: 0), "Their Info")
        XCTAssertEqual(control.titleForSegment(at: 1), "My Info for Them")
        XCTAssertEqual(control.selectedSegmentIndex, 0)
    }

    func testThreeOptionsRenderAsASegmentedControl() throws {
        let control = try XCTUnwrap(
            renderedSegmentedControl(for: choiceNode(options: ["A", "B", "C"]))
        )

        XCTAssertEqual(control.numberOfSegments, 3)
    }

    func testSegmentedControlOffersNoNoneRow() throws {
        let control = try XCTUnwrap(
            renderedSegmentedControl(for: choiceNode(options: ["Members", "Visibility"]))
        )

        let titles = (0 ..< control.numberOfSegments).map { control.titleForSegment(at: $0) }
        XCTAssertFalse(titles.contains("—"), "the picker must not offer a value Core rejects")
    }

    func testFifteenOptionsDoNotRenderAsASegmentedControl() throws {
        let options = (1 ... 15).map { "Theme \($0)" }

        XCTAssertNil(
            try renderedSegmentedControl(for: choiceNode(options: options)),
            "a long list stays a menu; fifteen segments would not fit a phone"
        )
    }

    func testStyleBoundaryIsThreeOptions() {
        XCTAssertEqual(PresentationNodeView.choiceStyle(optionCount: 2), .segmented)
        XCTAssertEqual(PresentationNodeView.choiceStyle(optionCount: 3), .segmented)
        XCTAssertEqual(PresentationNodeView.choiceStyle(optionCount: 4), .menu)
        XCTAssertEqual(PresentationNodeView.choiceStyle(optionCount: 15), .menu)
    }

    private func choiceNode(options: [String]) throws -> PresentationNode {
        let encodedOptions = options.enumerated().map { index, label in
            #"{"id":"opt\#(index)","label":"\#(label)","enabled":true}"#
        }.joined(separator: ",")
        let json = """
        {"Choice": {
          "binding_id": "perspective",
          "label": "Perspective",
          "selected": "opt0",
          "options": [\(encodedOptions)],
          "enabled": true,
          "accessibility": {"label": "Perspective options", "description": null}
        }}
        """
        return try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
    }

    /// Hosts the node in a window and returns the UIKit segmented control
    /// SwiftUI backs a `.segmented` picker with, or nil when none rendered.
    private func renderedSegmentedControl(for node: PresentationNode) -> UISegmentedControl? {
        let controller = UIHostingController(rootView: ChoiceHost(node: node))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return firstSegmentedControl(in: controller.view)
    }

    private func firstSegmentedControl(in view: UIView) -> UISegmentedControl? {
        if let control = view as? UISegmentedControl { return control }
        for child in view.subviews {
            if let found = firstSegmentedControl(in: child) { return found }
        }
        return nil
    }
}

private struct ChoiceHost: View {
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
