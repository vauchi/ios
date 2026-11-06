// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class BleStopAdvertisingDispatchTests: XCTestCase {
    private var tempDir: URL!
    private var repo: VauchiRepository!
    private var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "BLE Dispatch Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testBleStopAdvertisingForgetsTheAdvertisementToReplay() {
        viewModel.bleService.startAdvertising(
            serviceUuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            payload: Data([1, 2])
        )
        XCTAssertNotNil(viewModel.bleService.pendingAdvertise)

        viewModel.handleExchangeCommands([.bleStopAdvertising])

        XCTAssertNil(viewModel.bleService.pendingAdvertise)
    }
}
