// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// The camera view now survives surface updates (its identity no longer
// follows the per-revision binding id), so its coordinator must forward
// scans through the callback of the latest update. Kept from creation, the
// callback reported every scan under the first revision's binding, and Core
// dropped them all as stale: on the rig the iPhone decoded 893 of the Pixel's
// data frames and acknowledged none (issue #9, D14).
// Traces to: features/exchange.feature

@testable import Vauchi
import XCTest

final class MultipartCameraCallbackTests: XCTestCase {
    func testScansGoThroughTheLatestCallback() {
        var firstCallback: [String] = []
        let delivered = expectation(description: "the latest callback receives the scan")
        let coordinator = MultipartCameraPreview.Coordinator(onChunkScanned: { firstCallback.append($0) })

        coordinator.adopt(onChunkScanned: { code in
            XCTAssertEqual(code, "DATA-frame")
            delivered.fulfill()
        })
        coordinator.deliver("DATA-frame")

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(firstCallback, [])
    }

    /// The phone's own code can share the frame with the peer's; both must
    /// reach Core, which tells them apart (#450).
    func testEveryCodeInAFrameIsDelivered() {
        var received: [String] = []
        let delivered = expectation(description: "both codes are delivered")
        delivered.expectedFulfillmentCount = 2
        let coordinator = MultipartCameraPreview.Coordinator(onChunkScanned: {
            received.append($0)
            delivered.fulfill()
        })

        coordinator.deliverAll(["own-frame", "peer-frame"])

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(received, ["own-frame", "peer-frame"])
    }

    func testTheSameCodeTwiceInOneFrameBurstIsDeliveredOnce() {
        var received: [String] = []
        let delivered = expectation(description: "each distinct code is delivered")
        delivered.expectedFulfillmentCount = 2
        let coordinator = MultipartCameraPreview.Coordinator(onChunkScanned: {
            received.append($0)
            delivered.fulfill()
        })

        coordinator.deliverAll(["own-frame", "peer-frame"])
        coordinator.deliverAll(["own-frame", "peer-frame"])

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(received, ["own-frame", "peer-frame"])
    }
}
