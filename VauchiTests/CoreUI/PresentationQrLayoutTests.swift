// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Geometry of the exchange QR, measured off the rendered layout.
//
// Restores the guard the presentation-commands migration removed with
// `testGlanceScrollLayoutQrDisplayStaysLarge` (`8ea5370`): the exchange
// surface puts a display QR and a fixed-size camera preview in one
// non-scrolling stack, and the QR was the only flexible child, so it
// collapsed to ~104pt on a 667pt screen — far below what a dense
// multi-stage payload resolves at. A peer has to read it with a camera,
// so its size is a functional requirement, not a cosmetic one.
//
// See `_private/docs/problems/2026-08-17-ios-exchange-qr-collapses/`.
// Traces to: features/exchange.feature

import SwiftUI
@testable import Vauchi
import XCTest

final class PresentationQrLayoutTests: XCTestCase {
    private let displayQrJson = """
    {"Qr": {
      "id": "own_qr",
      "payloads": ["INI2W:OR51%KR4S8QYI*$BYIE4:2JAM.PPG9AWTQ7X3ZK1LMN5RSTUVW"],
      "purpose": "display",
      "label": "Show this",
      "accessibility": {"label": "Show this", "description": null}
    }}
    """

    /// The QR keeps a scannable size even when a sibling of fixed size is
    /// competing for the same vertical space.
    func testDisplayQrKeepsScannableSizeAgainstFixedSibling() throws {
        let node = try JSONDecoder().decode(
            PresentationNode.self,
            from: Data(displayQrJson.utf8)
        )

        let measured = renderedQrHeight(for: node)

        XCTAssertGreaterThanOrEqual(
            measured,
            PresentationNodeView.minimumScannableQr,
            "The exchange QR rendered \(measured)pt tall against a fixed-size "
                + "sibling; a peer camera needs at least "
                + "\(PresentationNodeView.minimumScannableQr)pt"
        )
    }

    /// Lays the node out in a viewport too small for both it and a
    /// 250pt sibling, and reports the height the QR actually got.
    private func renderedQrHeight(for node: PresentationNode) -> CGFloat {
        var measured: CGFloat = 0
        let controller = UIHostingController(
            rootView: CompetitionHost(node: node) { measured = $0 }
        )
        // SwiftUI only lays out — and so only reports geometry — for a view
        // that belongs to a window.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return measured
    }
}

/// Reproduces the exchange surface's shape: a display QR stacked with an
/// inflexible sibling standing in for the camera preview, in a viewport
/// that cannot fit both at full size.
private struct CompetitionHost: View {
    let node: PresentationNode
    let onMeasured: (CGFloat) -> Void
    @FocusState private var focused: String?

    var body: some View {
        VStack(spacing: 0) {
            PresentationNodeView(
                node: node,
                surfaceID: "surface",
                minimumTarget: 44,
                useFrontCamera: true,
                onCameraPermissionDenied: {},
                focusedBinding: $focused,
                onEvent: { _ in }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear { onMeasured(proxy.size.height) }
                }
            )
            Color.clear.frame(width: 250, height: 250)
        }
        .frame(width: 375, height: 400)
    }
}
