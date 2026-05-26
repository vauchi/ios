// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenNavigationTests.swift
// Guards the cross-tab navigation behaviour relied on by
// `CoreScreenView` (ios/Vauchi/CoreUI/CoreScreenView.swift).
//
// Bug repro:
// _private/docs/problems/2026-05-21-ios-shell-issues-from-walkthrough item 1.
// All `CoreScreenView`s on iOS share a single `AppViewModel`/engine, so
// a single `currentScreen` is multiplexed across every tab. When tab A
// drives the engine to screen X (e.g. More → Settings), then the user
// taps tab B (My Card), the tab-B view must re-assert its expected
// screen on appearance — otherwise tab B renders tab A's ScreenModel
// underneath its own native header.
//
// The previous implementation guarded `navigateTo` with a per-view
// `@State` that remembered the last screen it asked for and refused to
// re-issue the call. That guard silently broke cross-tab navigation:
// the second appearance of any tab was a no-op even though the shared
// engine had drifted. This test ensures the engine recovers when
// `navigateTo` is called repeatedly with different screen names.

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class CoreScreenNavigationTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!
    var viewModel: AppViewModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Nav Drift Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Scenario: My Card → More/Settings → My Card.
    ///
    /// Simulates the MainTabView tab sequence that triggered the
    /// walkthrough bug. After each navigateTo, `currentScreen.screenId`
    /// must match the requested screen — otherwise the new tab's
    /// CoreScreenContent body would render the previous tab's
    /// ScreenModel under its own native header.
    func testNavigateToRecoversFromCrossTabDrift() throws {
        viewModel.navigateTo(screenJson: "\"MyInfo\"")
        let afterMyInfo = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(afterMyInfo.screenId, "my_info",
                       "first nav must land on My Card")

        viewModel.navigateTo(screenJson: "\"Settings\"")
        let afterSettings = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(afterSettings.screenId, "settings",
                       "More → Settings nav must land on Settings")

        // Tab back to My Card: the engine has drifted to Settings; the
        // re-assertion that CoreScreenContent.task / .onAppear performs
        // on view re-appearance must bring the engine back to MyInfo.
        viewModel.navigateTo(screenJson: "\"MyInfo\"")
        let afterReturn = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(afterReturn.screenId, "my_info",
                       "tab-back to My Card must re-assert MyInfo even " +
                           "though another tab pushed Settings — without this " +
                           "recovery the home tab renders Settings under " +
                           "its own native header (walkthrough bug item 1)")
    }

    /// Scenario: navigating to the same screen twice in a row must be
    /// idempotent — no error, screen stays put. Guards the case where
    /// both `.task(id:)` and `.onAppear` fire on a single appearance.
    func testRepeatedNavigateToSameScreenIsIdempotent() throws {
        viewModel.navigateTo(screenJson: "\"MyInfo\"")
        viewModel.navigateTo(screenJson: "\"MyInfo\"")
        viewModel.navigateTo(screenJson: "\"MyInfo\"")
        let after = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(after.screenId, "my_info",
                       "redundant nav to the active screen is a no-op " +
                           "but must not corrupt the engine state")
    }

    /// Scenario: Groups tab → Contacts tab → Groups tab. Three-tab
    /// rotation, none of which is the More tab — defends against a
    /// regression where only the My Card path is fixed.
    ///
    /// The rendered ScreenModel's `screenId` is the canonical
    /// `AppScreen::screen_id()` that core 0.51.16 stamps for the five
    /// collapsed tab families (ADR-043 Am4, core commit d9798a0b):
    /// Groups navigation lands on "groups"; Contacts on "contacts"
    /// (previously the engine-emitted "groups_list"/"contact_list").
    func testGroupsContactsGroupsRotation() {
        viewModel.navigateTo(screenJson: "\"Groups\"")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "groups")

        viewModel.navigateTo(screenJson: "\"Contacts\"")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "contacts")

        viewModel.navigateTo(screenJson: "\"Groups\"")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "groups",
                       "Groups must re-assert after a Contacts detour")
    }

    /// Tier-1 data-driven tabs (ADR-043 Am4): forwarding the opaque
    /// `action_id` from `tabInfo()` as `UserAction::NavigateToTab` lands
    /// on the canonical screen. This is the dispatch path the
    /// data-driven `MainTabView` uses instead of constructing the domain
    /// variant string.
    func testNavigateToTabResolvesCanonicalScreen() {
        viewModel.navigateToTab(actionId: "groups")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "groups",
                       "NavigateToTab(\"groups\") must resolve to the groups screen")

        viewModel.navigateToTab(actionId: "contacts")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "contacts",
                       "NavigateToTab(\"contacts\") must resolve to the contacts screen")

        viewModel.navigateToTab(actionId: "my_info")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "my_info",
                       "NavigateToTab(\"my_info\") must resolve to the My Card screen")
    }

    /// CC-11 failure path: an unknown tab `action_id` must leave the
    /// engine on the last good screen — core rejects the token with a
    /// typed error, which iOS swallows rather than navigating to a wrong
    /// screen.
    func testNavigateToTabWithUnknownIdLeavesScreenUnchanged() {
        viewModel.navigateToTab(actionId: "my_info")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "my_info")

        viewModel.navigateToTab(actionId: "definitely_not_a_tab")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "my_info",
                       "unknown tab id must not change the current screen")
    }
}
