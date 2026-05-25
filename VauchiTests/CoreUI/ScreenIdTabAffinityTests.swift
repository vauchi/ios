// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ScreenIdTabAffinityTests.swift
// Pins AppViewModel.tab(forScreenId:) — the bottom-bar tab a core-emitted
// screen_id belongs to.

@testable import Vauchi
import XCTest

/// Guard for the zero-domain-vocab Tier-0 (c) narrow collapse.
///
/// Core is moving to emit the canonical `AppScreen::screen_id()`
/// (`contacts`, `groups`, `backup`, `sync`, `duress_pin`) instead of the
/// per-engine sub-state ids (`contact_list`, `groups_list`,
/// `backup_choose`, …). Unlike Android's `CoreScreenIdMap`, iOS navigates
/// by serde variant name and renders by components, so it needs **no**
/// map-compat fix — the only `screen_id`-driven behaviour that touches the
/// collapsed families is bottom-bar tab affinity, and it is prefix-based.
///
/// These tests pin that affinity for **both** the engine-emitted ids
/// (today) and the canonical ids (post-collapse), so a future tightening
/// of `screenIdPrefixToTab` (e.g. exact-match) can't silently desync the
/// tab pill once core flips.
final class ScreenIdTabAffinityTests: XCTestCase {
    func testCanonicalTabIdsMapToTheirTab() {
        XCTAssertEqual(AppViewModel.tab(forScreenId: "my_info"), "MyInfo")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "contacts"), "Contacts")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "exchange"), "Exchange")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "groups"), "Groups")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "more"), "More")
    }

    func testEngineEmittedIdsMapToTheSameTab() {
        // The pre-collapse ids the engines emit today. `hasPrefix` folds
        // them to the same tab as their canonical form above.
        XCTAssertEqual(AppViewModel.tab(forScreenId: "contact_list"), "Contacts")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "groups_list"), "Groups")
    }

    func testSubScreensMapToTheirParentTab() {
        // Detail/sub-screens stay under their parent tab via prefix.
        XCTAssertEqual(AppViewModel.tab(forScreenId: "contact_detail"), "Contacts")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "group_detail"), "Groups")
        XCTAssertEqual(AppViewModel.tab(forScreenId: "device_replacement"), "More")
    }

    func testCollapsedNonTabFamiliesReturnNil() {
        // Backup / Sync / Duress are not tabs — they stay on whatever tab
        // launched them. Both the canonical (post-collapse) and the
        // per-sub-state (pre-collapse) ids must yield nil so the collapse
        // never accidentally drives a tab switch.
        XCTAssertNil(AppViewModel.tab(forScreenId: "backup"))
        XCTAssertNil(AppViewModel.tab(forScreenId: "backup_choose"))
        XCTAssertNil(AppViewModel.tab(forScreenId: "sync"))
        XCTAssertNil(AppViewModel.tab(forScreenId: "sync_status"))
        XCTAssertNil(AppViewModel.tab(forScreenId: "duress_pin"))
        XCTAssertNil(AppViewModel.tab(forScreenId: "duress_overview"))
    }

    func testUnknownIdsReturnNil() {
        XCTAssertNil(AppViewModel.tab(forScreenId: ""))
        XCTAssertNil(AppViewModel.tab(forScreenId: "nonsense_screen_id"))
    }
}
