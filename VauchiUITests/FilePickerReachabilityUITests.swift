// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FilePickerReachabilityUITests.swift
// Verifies the ADR-031 file-picker (`ExchangeCommand::FilePickFromUser`)
// reaches the host's `.fileImporter` modifier from each user-facing
// trigger path. Closes the verification gap that hid two silent
// regressions:
//
//   1. Onboarding `restore_backup` — Phase 2B emits ExchangeCommands;
//      `OnboardingViewModel` previously dropped them with `break`.
//   2. MoreView "Import Contacts" — `ios!400` rewires the entry to
//      emit a core action, but the `.fileImporter` modifier only
//      lived on `CoreScreenView`; `MoreView` is a custom List, so the
//      picker host wasn't in the active hierarchy.
//
// What we assert: the `filepicker.pending` accessibility sentinel
// (mounted by `FilePickerModifier` while `coreVM.pendingFilePick` is
// non-nil) appears after the user-facing trigger. We deliberately do
// *not* poll the system picker process — its bundle id
// (`com.apple.DocumentManagerUICore`) and chrome labels drift across
// iOS versions, and once the bridge sets `pendingFilePick`, SwiftUI's
// `.fileImporter` is responsible for the actual presentation. The
// contract under test is "the bridge fires", not "the OS picker
// renders".
//
// Test ordering: XCTest sorts methods alphabetically within a class.
// Splitting into two classes (Onboarding* / Tabs*) keeps each test in
// its own bundle launch — fresh CI sims hit Onboarding first because
// no identity exists; the Tabs test seeds identity via
// `--reset-for-testing` itself, so order between classes doesn't
// matter.
//
// Traces to: features/onboarding.feature R-restore-backup,
// features/contacts.feature C-import-contacts.

import XCTest

// MARK: - Onboarding "Restore backup" → file picker

/// Phase 2B routes `restore_backup` through
/// `ActionResult.exchangeCommands{FilePickFromUser{ImportBackup}}`.
/// `OnboardingViewModel`'s bridge (`2026-05-04-ios-file-picker-hoist`
/// commit 2) forwards the command to `AppViewModel`, which sets
/// `pendingFilePick`; the root `.fileImporter` modifier observes it.
///
/// Today the test runs only when the simulator has no identity yet —
/// the in-app `--reset-for-testing` arg seeds identity (used by
/// AccessibilityUITests, which runs alphabetically before this class)
/// and there is no inverse wipe API exposed to launch arguments.
/// `XCTSkip` is used (rather than `XCTFail`) so a stale-identity sim
/// surfaces as a skip in the test report instead of breaking the
/// suite.
final class OnboardingFilePickerReachabilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testRestoreBackupTriggersFilePicker() throws {
        app.launch()

        let haveIdentity = app.buttons["have_identity"]
        guard haveIdentity.waitForExistence(timeout: 10) else {
            throw XCTSkip(
                "Sim has stale identity (likely seeded by a prior test) — " +
                    "no `wipe-for-testing` arg exists yet to reset state."
            )
        }
        haveIdentity.tap()

        let restoreBackup = app.buttons["restore_backup"]
        XCTAssertTrue(restoreBackup.waitForExistence(timeout: 5),
                      "LinkChoice should expose the 'Restore backup' affordance")
        restoreBackup.tap()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "filepicker.pending").firstMatch.waitForExistence(timeout: 10),
            "AppViewModel.pendingFilePick should flip non-nil after Onboarding 'Restore backup'"
        )
    }
}

// MARK: - Tabs MoreView "Import Contacts" → file picker

/// `ios!400` rewired MoreView's "Import Contacts" entry to navigate
/// the engine to AppScreen::More then emit `import_contacts`. Core's
/// MoreEngine returns `ExchangeCommand::FilePickFromUser`. The
/// `.fileImporter` host hoisted in `2026-05-04-ios-file-picker-hoist`
/// to ContentView root must observe `pendingFilePick` and present.
final class TabsFilePickerReachabilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testMoreViewImportContactsTriggersFilePicker() {
        app.launchArguments = ["--reset-for-testing"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10),
                      "Tab bar should appear after --reset-for-testing")

        let moreTab = tabBar.buttons.element(boundBy: 4)
        moreTab.tap()

        let importContacts = app.buttons["more.importContacts"]
        XCTAssertTrue(importContacts.waitForExistence(timeout: 5),
                      "MoreView should render the 'Import Contacts' affordance")
        importContacts.tap()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "filepicker.pending").firstMatch.waitForExistence(timeout: 10),
            "AppViewModel.pendingFilePick should flip non-nil after 'Import Contacts'"
        )
    }
}
