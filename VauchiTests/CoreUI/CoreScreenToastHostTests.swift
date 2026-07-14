// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Reachability guard: the main core-driven screen tree
// (`CoreScreenView` → `CoreScreenContent`) must host
// `ActionResult.ShowToast`. Toast is not a ScreenModel component, so each
// screen tree needs its own result host. The onboarding tree got one in
// `2026-06-11-ios-onboarding-alert-host-missing`, but the main tree did
// not — a core-emitted toast (archive contact, device management, …) set
// `coreVM.toastMessage` with nothing observing it, and was silently dropped
// (silent-failure umbrella under `2026-06-11-store-submission-blockers`).
//
// Unlike `ActionResultAlertToastTests` (VM state-flip, which flips identically
// whether or not a host exists), this drives the real SwiftUI tree. It asserts
// on *rendered pixels* rather than the accessibility tree, because SwiftUI does
// not vend its accessibility nodes to a unit test where VoiceOver never runs.
// The toast renders top-aligned; the loading spinner is centred, so comparing
// only the top strip isolates the toast: if no host observes `toastMessage`,
// setting it changes nothing and the two renders are byte-identical.

import SwiftUI
@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class CoreScreenToastHostTests: XCTestCase {
    var tempDir: URL!
    var viewModel: VauchiViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        viewModel = VauchiViewModel(dataDir: tempDir.path, relayUrl: nil)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_main_screen_tree_hosts_show_toast() throws {
        let coreVM = try XCTUnwrap(
            viewModel.coreViewModel,
            "repository must initialize (protected data is available on simulator)"
        )

        coreVM.toastMessage = nil
        let baseline = try XCTUnwrap(Self.renderTopStrip(of: makeScreenView()))

        coreVM.toastMessage = Self.toastProbe
        let withToast = try XCTUnwrap(Self.renderTopStrip(of: makeScreenView()))

        XCTAssertNotEqual(
            withToast,
            baseline,
            "Setting coreVM.toastMessage changed nothing in the top region — "
                + "CoreScreenContent has no ActionResult.ShowToast host"
        )
    }

    private func makeScreenView() -> some View {
        CoreScreenView(renderingCurrentScreen: ())
            .environmentObject(viewModel)
    }

    private static let toastProbe = "Toast host probe a91c"
    private static let canvas = CGRect(x: 0, y: 0, width: 390, height: 844)
    /// Top strip that captures the top-aligned toast while excluding the
    /// centred loading spinner (the only animated element on the screen).
    private static let toastStripHeight: CGFloat = 160

    /// Hosts `view` in a key window, lets SwiftUI commit, then captures the
    /// PNG of the top strip of the rendered hierarchy.
    private static func renderTopStrip(of view: some View) -> Data? {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: canvas)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = canvas
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let stripBounds = CGRect(x: 0, y: 0, width: canvas.width, height: toastStripHeight)
        let image = UIGraphicsImageRenderer(bounds: stripBounds, format: format).image { _ in
            host.view.drawHierarchy(in: canvas, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image.pngData()
    }
}
