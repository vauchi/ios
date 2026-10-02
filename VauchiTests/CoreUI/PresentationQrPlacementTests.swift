// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core may send a display code's `placement`: its side and the offset of
// its top-left corner, in permille of the node's square. Absent means the
// code fills the square. The shell draws where it is told and never
// outside its own square (#450).
//
// Traces to: features/generic_presentation_protocol.feature

@testable import Vauchi
import XCTest

final class PresentationQrPlacementTests: XCTestCase {
    private func decodeQr(placement: String?) throws -> PresentationNode.QrCode {
        let field = placement.map { "\"placement\": \($0)," } ?? ""
        let json = """
        {"Qr": {
          "id": "own_qr",
          "payloads": ["FRAME"],
          "purpose": "display",
          "label": null,
          \(field)
          "accessibility": {"label": "Your code", "description": null}
        }}
        """
        let node = try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
        guard case let .qr(value) = node else {
            XCTFail("expected a QR node")
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }

    func testAPlacementIsDecodedInPermille() throws {
        let value = try decodeQr(placement: #"{"size": 650, "x": 350, "y": 175}"#)

        XCTAssertEqual(value.placement, QrPlacement(size: 650, x: 350, y: 175))
    }

    func testAnAbsentPlacementLeavesTheCodeFillingItsSquare() throws {
        XCTAssertNil(try decodeQr(placement: nil).placement)
    }

    func testAFullSquareDrawsTheCodeEdgeToEdge() {
        XCTAssertEqual(
            QrFrameSpec(placement: nil, squareSide: 320),
            QrFrameSpec(side: 320, left: 0, top: 0)
        )
    }

    func testAPlacedCodeIsScaledAndOffsetWithinTheSquare() {
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: 650, x: 350, y: 175), squareSide: 320),
            QrFrameSpec(side: 208, left: 112, top: 56)
        )
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: 800, x: 200, y: 0), squareSide: 320),
            QrFrameSpec(side: 256, left: 64, top: 0)
        )
    }

    /// Core never sends these; a shell still must not draw past its node.
    func testAPlacementReachingOutsideTheSquareIsPulledBackInside() {
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: 800, x: 900, y: 5000), squareSide: 320),
            QrFrameSpec(side: 256, left: 64, top: 64)
        )
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: 4000, x: 10, y: 10), squareSide: 320),
            QrFrameSpec(side: 320, left: 0, top: 0)
        )
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: 500, x: -20, y: -1), squareSide: 320),
            QrFrameSpec(side: 160, left: 0, top: 0)
        )
    }

    func testANonsensicalSizeFallsBackToTheFullSquare() {
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: 0, x: 0, y: 0), squareSide: 320),
            QrFrameSpec(side: 320, left: 0, top: 0)
        )
        XCTAssertEqual(
            QrFrameSpec(placement: QrPlacement(size: -5, x: 0, y: 0), squareSide: 320),
            QrFrameSpec(side: 320, left: 0, top: 0)
        )
    }
}
