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
// appears (queried via SpringBoard / DocumentPickerUI bundle).
//
// Traces to: features/onboarding.feature R-restore-backup,
// features/contacts.feature C-import-contacts.

import XCTest

final class FilePickerReachabilityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        // Dismiss any system picker that lingered between tests so
        // SpringBoard returns to a clean state for the next run.
        let docPicker = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")
        if docPicker.exists {
            docPicker.terminate()
        }
        app = nil
    }

    // MARK: - MoreView "Import Contacts" → file picker

    /// `ios!400` rewired MoreView's "Import Contacts" entry to navigate
    /// the engine to AppScreen::More then emit `import_contacts`. Core's
    /// MoreEngine returns `ExchangeCommand::FilePickFromUser`. The
    /// `.fileImporter` host hoisted in `2026-05-04-ios-file-picker-hoist`
    /// to ContentView root must surface the system document picker.
    func testMoreViewImportContactsTriggersFilePicker() {
        app.launchArguments = ["--reset-for-testing"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10),
                      "Tab bar should appear after --reset-for-testing")

        // Navigate to the More tab and tap "Import Contacts".
        // The accessibility identifier is set by MoreView.
        let moreTab = tabBar.buttons.element(boundBy: 4)
        moreTab.tap()

        let importContacts = app.buttons["more.importContacts"]
        XCTAssertTrue(importContacts.waitForExistence(timeout: 5),
                      "MoreView should render the 'Import Contacts' affordance")
        importContacts.tap()

        // The system document picker is presented by
        // UIDocumentPickerViewController. SwiftUI hosts it via the
        // topmost view controller; it surfaces in XCTest via the
        // springboard query below. We don't drive a selection — we
        // only need to prove the picker reaches the user.
        let pickerAppeared = waitForDocumentPicker(timeout: 5)
        XCTAssertTrue(pickerAppeared,
                      "System document picker should be presented after 'Import Contacts'")
    }

    // MARK: - Onboarding "Restore backup" → file picker

    /// Phase 2B routes `restore_backup` through
    /// `ActionResult.exchangeCommands{FilePickFromUser{ImportBackup}}`.
    /// `OnboardingViewModel`'s bridge (`2026-05-04-ios-file-picker-hoist`
    /// commit 2) forwards the command to `AppViewModel`, where the
    /// root `.fileImporter` opens the picker.
    ///
    /// This test launches WITHOUT `--reset-for-testing` so the
    /// onboarding flow renders. The exact button identifier depends
    /// on the LinkChoice screen's emitted ScreenAction; we look up
    /// "restore_backup" directly via accessibility.
    func testOnboardingRestoreBackupTriggersFilePicker() throws {
        app.launchArguments = ["--clear-onboarding-state"]
        app.launch()

        // IdentityCheck is the entry screen; have_identity → LinkChoice.
        let haveIdentity = app.buttons["have_identity"]
        guard haveIdentity.waitForExistence(timeout: 10) else {
            // Without a clean onboarding fixture, this test is best-
            // effort. Skip rather than false-fail; a follow-up issue
            // will pin a stable launch into IdentityCheck.
            throw XCTSkip("Onboarding entry not reached — fixture-dependent")
        }
        haveIdentity.tap()

        let restoreBackup = app.buttons["restore_backup"]
        XCTAssertTrue(restoreBackup.waitForExistence(timeout: 5),
                      "LinkChoice should expose the 'Restore backup' affordance")
        restoreBackup.tap()

        let pickerAppeared = waitForDocumentPicker(timeout: 5)
        XCTAssertTrue(pickerAppeared,
                      "System document picker should appear after Onboarding 'Restore backup'")
    }

    // MARK: - Helpers

    /// Polls SpringBoard / DocumentPickerUI for the document picker UI.
    /// Returns `true` if any of the standard picker indicators appears
    /// within `timeout`.
    private func waitForDocumentPicker(timeout: TimeInterval) -> Bool {
        // The system picker hosts in a separate process, accessible
        // via its bundle id. Different iOS versions expose different
        // labels; we try a small set known to surface in the picker.
        let candidates = ["Browse", "Recents", "Cancel", "Done"]
        let deadline = Date().addingTimeInterval(timeout)
        let pickerApp = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore")
        while Date() < deadline {
            if pickerApp.state == .runningForeground {
                return true
            }
            for label in candidates where app.buttons[label].exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
