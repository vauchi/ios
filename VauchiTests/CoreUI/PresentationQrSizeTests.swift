// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core may ask for a display code's square at `size: "compact"` on a short
// window, so the camera under the code keeps room: on an iPhone SE the
// Glance camera was 6 x 11 pt beside a 320 pt code (vauchi/private#513).
// Absent or unknown means the standard square.
//
// Traces to: features/generic_presentation_protocol.feature

@testable import Vauchi
import XCTest

final class PresentationQrSizeTests: XCTestCase {
    private func decodeQr(size: String?) throws -> PresentationNode.QrCode {
        let field = size.map { "\"size\": \"\($0)\"," } ?? ""
        let json = """
        {"Qr": {
          "id": "own_qr",
          "payloads": ["CODE"],
          "purpose": "display",
          "label": null,
          \(field)
          "accessibility": {"label": "Show this to exchange", "description": null}
        }}
        """
        let node = try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
        guard case let .qr(value) = node else {
            XCTFail("expected a QR node")
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }

    func testACompactSizeIsDecodedAndDrawnSmaller() throws {
        let value = try decodeQr(size: "compact")

        XCTAssertEqual(value.size, "compact")
        XCTAssertEqual(qrSquareSide(value.size), 240)
    }

    func testAnAbsentOrUnknownSizeDrawsTheStandardSquare() throws {
        XCTAssertNil(try decodeQr(size: nil).size)
        XCTAssertEqual(qrSquareSide(nil), 320)
        XCTAssertEqual(qrSquareSide("standard"), 320)
        XCTAssertEqual(qrSquareSide("huge"), 320)
    }
}
