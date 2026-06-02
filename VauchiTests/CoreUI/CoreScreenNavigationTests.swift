// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreScreenNavigationTests.swift
// Guards the cross-tab navigation behaviour the main shell relies on.
//
// Bug repro:
// _private/docs/problems/2026-05-21-ios-shell-issues-from-walkthrough item 1.
// Every tab shares a single `AppViewModel`/engine, so one `currentScreen`
// is multiplexed across the whole shell. When the engine drifts to screen
// X (e.g. a sub-screen), selecting another tab must re-assert that tab's
// canonical screen — otherwise the shell renders the previous screen's
// ScreenModel.
//
// Navigation is now selection-driven: the custom `CoreBottomTabBar`
// dispatches `UserAction::NavigateToTab(action_id)` on tap, and the single
// `MainContentView` renders whatever core returns (the old per-view
// lifecycle `navigateTo` re-assert + its `@State` guard — and
// `navigateTo(screenJson:)` itself — were retired in
// `2026-06-02-ios-exchange-flow-core-driven` S3). These tests drive that
// same `navigateToTab` path directly.

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

    /// Scenario: My Card → Groups → My Card.
    ///
    /// Simulates the tab sequence that triggered the walkthrough bug.
    /// After each `navigateToTab`, `currentScreen.screenId` must match the
    /// selected tab — otherwise the shell would render the previous tab's
    /// ScreenModel. The tab-back to My Card must re-assert MyInfo even
    /// though the engine had drifted to Groups.
    func testNavigateToTabRecoversFromCrossTabDrift() throws {
        viewModel.navigateToTab(actionId: "my_info")
        let afterMyInfo = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(afterMyInfo.screenId, "my_info",
                       "first nav must land on My Card")

        viewModel.navigateToTab(actionId: "groups")
        let afterGroups = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(afterGroups.screenId, "groups",
                       "Groups tab must land on the groups screen")

        // Tab back to My Card: the engine has drifted to Groups; selecting
        // the My Card tab must bring it back to MyInfo — without this the
        // home tab would render Groups (walkthrough bug item 1).
        viewModel.navigateToTab(actionId: "my_info")
        let afterReturn = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(afterReturn.screenId, "my_info",
                       "tab-back to My Card must re-assert MyInfo even " +
                           "though another tab pushed Groups")
    }

    /// Scenario: selecting the same tab repeatedly must be idempotent —
    /// no error, screen stays put. Guards the case where the tab body
    /// re-asserts on every appearance.
    func testRepeatedNavigateToTabSameTabIsIdempotent() throws {
        viewModel.navigateToTab(actionId: "my_info")
        viewModel.navigateToTab(actionId: "my_info")
        viewModel.navigateToTab(actionId: "my_info")
        let after = try XCTUnwrap(viewModel.currentScreen)
        XCTAssertEqual(after.screenId, "my_info",
                       "redundant nav to the active tab is a no-op " +
                           "but must not corrupt the engine state")
    }

    /// Scenario: Groups tab → Contacts tab → Groups tab. Three-tab
    /// rotation, none of which is the My Card path — defends against a
    /// regression where only the home path is fixed.
    ///
    /// The rendered ScreenModel's `screenId` is the canonical
    /// `AppScreen::screen_id()` core stamps for the collapsed tab families
    /// (ADR-043 Am4): Groups → "groups"; Contacts → "contacts".
    func testGroupsContactsGroupsRotation() {
        viewModel.navigateToTab(actionId: "groups")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "groups")

        viewModel.navigateToTab(actionId: "contacts")
        XCTAssertEqual(viewModel.currentScreen?.screenId, "contacts")

        viewModel.navigateToTab(actionId: "groups")
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
