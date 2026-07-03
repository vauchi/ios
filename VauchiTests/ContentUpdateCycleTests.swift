// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// The content-update check→apply→decide sequencing lives in core
// (`DomainCommand::RunContentUpdateCycle`, exhaustively covered by
// core's `content_cycle_outcome` table test). All that remains on the
// iOS side is the pure decision "given the cycle outcome, which native
// follow-ups fire": re-apply the theme when the appearance changed, and
// reload the UI when anything was applied. That decision is
// `VauchiViewModel.contentCycleActions`, fully covered here.
//
// The detached dispatch + MainActor theme/reload calls in
// `runContentUpdateCycle(appEngine:)` are thin glue over this decision
// and an engine, so they are not unit-tested. Mirrors macOS
// `ContentUpdateCycleTests`.

@testable import Vauchi
import VauchiPlatform
import XCTest

final class ContentUpdateCycleTests: XCTestCase {
    private func outcome(
        applied: Bool,
        retryableFailure: Bool = false,
        refreshAppearance: Bool = false
    ) -> MobileContentCycleOutcome {
        MobileContentCycleOutcome(
            applied: applied,
            retryableFailure: retryableFailure,
            refreshAppearance: refreshAppearance
        )
    }

    /// Nothing applied (up-to-date / disabled) → no native follow-up.
    func testNothingAppliedTriggersNoActions() {
        let actions = VauchiViewModel.contentCycleActions(outcome(applied: false))
        XCTAssertFalse(actions.refreshTheme)
        XCTAssertFalse(actions.reloadUI)
    }

    /// A retryable failure at startup is best-effort: iOS fires the
    /// cycle once on launch and never retries. A failure applies
    /// nothing, so it must drive no follow-up.
    func testRetryableFailureTriggersNoActions() {
        let actions = VauchiViewModel.contentCycleActions(
            outcome(applied: false, retryableFailure: true)
        )
        XCTAssertFalse(actions.refreshTheme)
        XCTAssertFalse(actions.reloadUI)
    }

    /// Non-appearance content applied (e.g. locales) → reload the UI so
    /// the new content renders, but do not touch the theme.
    func testAppliedWithoutAppearanceReloadsOnly() {
        let actions = VauchiViewModel.contentCycleActions(
            outcome(applied: true, refreshAppearance: false)
        )
        XCTAssertFalse(actions.refreshTheme)
        XCTAssertTrue(actions.reloadUI)
    }

    /// Themes changed → re-apply the selected theme through the native
    /// appearance API *and* reload the UI.
    func testAppliedWithAppearanceRefreshesThemeAndReloads() {
        let actions = VauchiViewModel.contentCycleActions(
            outcome(applied: true, refreshAppearance: true)
        )
        XCTAssertTrue(actions.refreshTheme)
        XCTAssertTrue(actions.reloadUI)
    }
}
