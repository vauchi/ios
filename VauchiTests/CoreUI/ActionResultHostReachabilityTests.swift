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
// Onboarding no longer has a distinct view tree: `ee946dd` removed
// `CoreOnboardingView` and unified onboarding under
// `ContentView`/`CoreScreenView` — core emits the onboarding screen as a
// normal screen. Its host guard therefore collapses into the main ×
// ShowAlert cell here plus `CoreScreenToastHostTests` (main × ShowToast);
// there is no separate onboarding tree left that could drop a host.
//
// - The alert cell asserts that flipping `coreVM.alertMessage` makes the
//   hosting controller present a modal. Presentation happens in-process
//   from our own window — if no `.alert` host is bound in the tree,
//   nothing presents. This observes our own view tree's presentation
//   state, not a foreign process or system chrome labels (CC-23).

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

    // MARK: - Tree factories

    private func makeMainView() -> some View {
        CoreScreenView(renderingCurrentScreen: ())
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

    private static let alertTitleProbe = "Alert host probe 7f3e"
    private static let alertBodyProbe = "Alert body probe 7f3e"
    private static let canvas = CGRect(x: 0, y: 0, width: 390, height: 844)
}
