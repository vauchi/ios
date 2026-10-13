// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core sends ResetApplication after a wipe: the shell resets the state it
// owns and shows Core's first screen. Kept, the old profile still named
// the wipe screen active, so the iPhone stayed on Emergency Data Wipe with
// Welcome's tab bar under it, and the wiped screens stayed in memory
// (vauchi/private#293).
//
// Traces to: features/generic_presentation_protocol.feature

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class ResetApplicationTests: XCTestCase {
    private var tempDir: URL!
    private var repo: VauchiRepository!
    private var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Reset Application Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testResetDropsTheScreensAndProfileShownBeforeIt() throws {
        viewModel.receivePresentationEnvelope("""
        {"commands":[
          {"ReplaceSurface":{"surface":{
            "surface_id":"wiped_screen",
            "revision":1000,
            "title":"Emergency Data Wipe",
            "subtitle":null,
            "accessibility_label":"Emergency Data Wipe",
            "layout":"scroll",
            "tokens":{
              "spacing_small":4,
              "spacing_medium":8,
              "spacing_large":16,
              "corner_radius":8,
              "minimum_target_size":44
            },
            "nodes":[]
          }}},
          {"SetPresentationProfile":{"profile":{
            "window_class":"compact",
            "pane_layout":"single",
            "primary_surface":"wiped_screen",
            "detail_surface":null,
            "active_surface":"wiped_screen"
          }}},
          "ResetApplication"
        ]}
        """)

        XCTAssertNil(viewModel.alertMessage)
        XCTAssertNil(viewModel.presentationState.surfaces["wiped_screen"])
        let active = try XCTUnwrap(viewModel.presentationState.activeSurfaceID)
        XCTAssertNotEqual(active, "wiped_screen")
        XCTAssertEqual(viewModel.presentationState.visibleSurfaceIDs, [active])
    }
}
