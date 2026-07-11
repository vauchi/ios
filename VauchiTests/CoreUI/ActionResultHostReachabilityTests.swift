// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Reachability guards: every screen tree must host the modal-class
// `ActionResult`s — `ShowAlert` and `ShowToast` — goal 2 of
// `2026-06-11-silent-failure-mode-umbrella`. An `AppViewModel`
// state-flip test cannot catch a missing host: the VM flips its
// `@Published` state identically whether or not a host observes it,
// and the message is silently dropped.
//
// - Toast cells assert on rendered pixels of the top strip (same
//   technique and rationale as `CoreScreenToastHostTests`, which owns
//   the main × ShowToast cell).
// - Alert cells assert that flipping `alertMessage` makes the hosting
//   controller present a modal. Presentation happens in-process from
//   our own window — if no `.alert` host is bound in the tree, nothing
//   presents. This observes our own view tree's presentation state,
//   not a foreign process or system chrome labels (CC-23).

import SwiftUI
@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class ActionResultHostReachabilityTests: XCTestCase {
    var tempDir: URL!
    var viewModel: VauchiViewModel!
    private var window: UIWindow?

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        viewModel = VauchiViewModel(dataDir: tempDir.path, relayUrl: nil)
    }

    override func tearDownWithError() throws {
        window?.isHidden = true
        window = nil
        viewModel = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - onboarding × ShowToast

    func test_onboarding_tree_hosts_show_toast() throws {
        let coreVM = try XCTUnwrap(
            viewModel.coreViewModel,
            "repository must initialize (protected data is available on simulator)"
        )

        coreVM.toastMessage = nil
        let baseline = try XCTUnwrap(Self.renderTopStrip(of: makeOnboardingView()))

        coreVM.toastMessage = Self.toastProbe
        let withToast = try XCTUnwrap(Self.renderTopStrip(of: makeOnboardingView()))

        XCTAssertNotEqual(
            withToast,
            baseline,
            "Setting coreVM.toastMessage changed nothing in the top region — "
                + "CoreOnboardingContent has no ActionResult.ShowToast host"
        )
    }

    // MARK: - main × ShowAlert

    func test_main_screen_tree_hosts_show_alert() throws {
        let coreVM = try XCTUnwrap(
            viewModel.coreViewModel,
            "repository must initialize (protected data is available on simulator)"
        )

        let host = mount(makeMainView())
        Self.pump(seconds: 0.5)
        XCTAssertNil(
            host.presentedViewController,
            "nothing should be presented before the probe flips alertMessage"
        )

        coreVM.alertMessage = .init(title: Self.alertTitleProbe, message: Self.alertBodyProbe)

        XCTAssertTrue(
            Self.pumpUntil { host.presentedViewController != nil },
            "Main tree dropped ActionResult.ShowAlert — no .alert host bound "
                + "to coreVM.alertMessage in CoreScreenContent"
        )
    }

    // MARK: - onboarding × ShowAlert

    func test_onboarding_tree_hosts_show_alert() throws {
        let coreVM = try XCTUnwrap(
            viewModel.coreViewModel,
            "repository must initialize (protected data is available on simulator)"
        )

        let host = mount(makeOnboardingView())
        Self.pump(seconds: 0.5)
        XCTAssertNil(
            host.presentedViewController,
            "nothing should be presented before the probe flips alertMessage"
        )

        coreVM.alertMessage = .init(title: Self.alertTitleProbe, message: Self.alertBodyProbe)

        XCTAssertTrue(
            Self.pumpUntil { host.presentedViewController != nil },
            "Onboarding tree dropped ActionResult.ShowAlert — no .alert host "
                + "bound to coreVM.alertMessage in CoreOnboardingContent"
        )
    }

    // MARK: - Tree factories

    private func makeMainView() -> some View {
        CoreScreenView(renderingCurrentScreen: ())
            .environmentObject(viewModel)
    }

    private func makeOnboardingView() -> some View {
        CoreOnboardingView(onIdentityCreated: {})
            .environmentObject(viewModel)
    }

    // MARK: - Hosting + run-loop helpers

    /// Hosts `view` in a key window kept alive for the test (presentation
    /// requires the hosting controller to stay in a visible window).
    private func mount(_ view: some View) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: AnyView(view))
        let window = UIWindow(frame: Self.canvas)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = Self.canvas
        host.view.layoutIfNeeded()
        self.window = window
        return host
    }

    private static func pump(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Pumps the run loop in short slices until `condition` holds or the
    /// deadline passes. Bounded wait-for-state, not a fixed sleep: alert
    /// presentation is animated, so a single pass cannot observe it.
    private static func pumpUntil(
        deadline: TimeInterval = 5.0,
        _ condition: () -> Bool
    ) -> Bool {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private static let toastProbe = "Toast host probe 7f3e"
    private static let alertTitleProbe = "Alert host probe 7f3e"
    private static let alertBodyProbe = "Alert body probe 7f3e"
    private static let canvas = CGRect(x: 0, y: 0, width: 390, height: 844)
    /// Top strip captures the top-aligned toast while excluding the centred
    /// loading spinner (the only animated element on the screen).
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
