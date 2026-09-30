// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// A camera node's binding id changes with every surface revision, so stale
// scans can be told apart. Used as the view's identity, it made SwiftUI build
// a new camera preview, and a new AVCaptureSession, on every progress update:
// about once a second during a Hover transfer, which at 17 cm kept the camera
// from ever settling (exchange journal D14, issue #9).
// Traces to: features/exchange.feature

@testable import Vauchi
import XCTest

final class PresentationCaptureIdentityTests: XCTestCase {
    private func captureNode(bindingID: String) throws -> PresentationNode {
        let json = """
        {"Qr": {
          "id": "\(bindingID)",
          "payloads": [],
          "purpose": "capture",
          "label": "Scan their code",
          "accessibility": {"label": "Scan their code", "description": null}
        }}
        """
        return try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
    }

    private func displayNode(id: String) throws -> PresentationNode {
        let json = """
        {"Qr": {
          "id": "\(id)",
          "payloads": ["INI2W:OR51%KR4S8QYI"],
          "purpose": "display",
          "label": null,
          "accessibility": {"label": "Show this", "description": null}
        }}
        """
        return try JSONDecoder().decode(PresentationNode.self, from: Data(json.utf8))
    }

    func testCameraKeepsItsViewIdentityAcrossSurfaceRevisions() throws {
        let before = try identifyPresentationNodes([captureNode(bindingID: "surface.7.binding.0")])
        let after = try identifyPresentationNodes([captureNode(bindingID: "surface.8.binding.0")])

        XCTAssertEqual(before.map(\.id), after.map(\.id))
    }

    func testDisplayQrKeepsItsIdBasedIdentity() throws {
        let identified = try identifyPresentationNodes([displayNode(id: "own_qr")])

        XCTAssertEqual(identified.map(\.id), ["qr:own_qr"])
    }
}
