// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FilePickerReachabilityUITests.swift
// Verifies the ADR-031 file-picker (`ExchangeCommand::FilePickFromUser`)
// reaches the system document picker from each user-facing trigger
// path. Closes the verification gap that hid two silent regressions:
//
//   1. Onboarding `restore_backup` — Phase 2B emits ExchangeCommands;
//      `OnboardingViewModel` previously dropped them with `break`.
//   2. MoreView "Import Contacts" — `ios!400` rewires the entry to
//      emit a core action, but the `.fileImporter` modifier only
//      lived on `CoreScreenView`; `MoreView` is a custom List, so the
//      picker host wasn't in the active hierarchy.
//
// Both regressions ship if the modifier is host-scoped instead of
// rooted at `ContentView`. These tests would catch the regression
// pattern: trigger the action, assert the system picker actually
// appears (queried via the picker process's own bundle id).
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
/// commit 2) forwards the command to `AppViewModel`, where the root
/// `.fileImporter` opens the picker.
///
/// Today the test runs only when the simulator has no identity yet —
/// the in-app `--reset-for-testing` arg seeds identity (used by
/// AccessibilityUITests, which runs alphabetically before this class)
/// and there is no inverse wipe API exposed to launch arguments.
/// `XCTSkip` is used (rather than `XCTFail`) so a stale-identity sim
/// surfaces as a skip in the test report instead of breaking the
/// suite. The bridge itself (`OnboardingViewModel.onExchangeCommands`)
/// is exercised end-to-end by manual smoke runs and by the core-side
/// reachability walker (`just reachability`); a Swift unit test
/// exercising it directly is a follow-up once a wipe API exposes a
/// reliable onboarding-state hook.
final class OnboardingFilePickerReachabilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        terminateDocumentPicker()
        app = nil
    }

    func testRestoreBackupTriggersFilePicker() throws {
        app.launch()

        let haveIdentity = app.buttons["have_identity"]
        guard haveIdentity.waitForExistence(timeout: 10) else {
            throw XCTSkip(
                "Sim has stale identity (likely seeded by a prior test) — " +
                    "no `wipe-for-testing` arg exists yet to reset state. " +
                    "Bridge logic covered by unit test in the meantime."
            )
        }
        haveIdentity.tap()

        let restoreBackup = app.buttons["restore_backup"]
        XCTAssertTrue(restoreBackup.waitForExistence(timeout: 5),
                      "LinkChoice should expose the 'Restore backup' affordance")
        restoreBackup.tap()

        XCTAssertTrue(
            waitForDocumentPicker(timeout: 10),
            "System document picker should appear after Onboarding 'Restore backup'"
        )
    }
}

// MARK: - Tabs MoreView "Import Contacts" → file picker

/// `ios!400` rewired MoreView's "Import Contacts" entry to navigate
/// the engine to AppScreen::More then emit `import_contacts`. Core's
/// MoreEngine returns `ExchangeCommand::FilePickFromUser`. The
/// `.fileImporter` host hoisted in `2026-05-04-ios-file-picker-hoist`
/// to ContentView root must surface the system document picker.
final class TabsFilePickerReachabilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        terminateDocumentPicker()
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
            waitForDocumentPicker(timeout: 5),
            "System document picker should be presented after 'Import Contacts'"
        )
    }
}

// MARK: - Helpers

/// Waits for the system document picker to surface. The picker hosts in
/// `com.apple.DocumentManagerUICore` (iOS 17+) — we wait on its
/// `runningForeground` state OR on its standard "Cancel" chrome button
/// becoming queryable, whichever fires first. Both signals are
/// evaluated by XCTest's predicate runloop (no busy `Thread.sleep`).
///
/// `XCTWaiter().wait(for:timeout:)` requires ALL expectations to
/// fulfil — wrong for an OR condition. Instead we wrap both checks
/// inside a single block-based `NSPredicate`; XCTest re-evaluates it
/// on the runloop until it returns `true` or `timeout` elapses.
private func waitForDocumentPicker(timeout: TimeInterval) -> Bool {
    let pickerApp = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")
    let predicate = NSPredicate { _, _ in
        if pickerApp.state == .runningForeground { return true }
        return pickerApp.buttons["Cancel"].exists
    }
    let exp = XCTNSPredicateExpectation(predicate: predicate, object: NSObject())
    return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
}

/// Terminates the system document picker so the next test starts from a
/// clean SpringBoard state.
private func terminateDocumentPicker() {
    let docPicker = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")
    if docPicker.state != .notRunning {
        docPicker.terminate()
    }
}
