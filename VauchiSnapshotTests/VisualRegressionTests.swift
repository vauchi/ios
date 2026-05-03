// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VisualRegressionTests.swift
// Snapshot tests for all SwiftUI views
// Based on: VRT implementation plan Phase 2

import SnapshotTesting
import SwiftUI
@testable import Vauchi
import XCTest

/// Visual regression tests for all major views.
///
/// Uses swift-snapshot-testing with View-based rendering (not UIHostingController)
/// for simulator-independent snapshots. This ensures baselines match regardless
/// of which iOS Simulator device CI uses.
///
/// Layout: 390x844 pt (iPhone Pro logical size) at 2x scale = 780x1688 px.
@MainActor
final class VisualRegressionTests: XCTestCase {
    /// Fixed layout matching iPhone Pro logical size at 2x scale.
    /// Simulator-independent: the snapshot library renders at the exact specified
    /// dimensions regardless of the host simulator's native display scale.
    private let screenLayout: SwiftUISnapshotLayout = .fixed(width: 390, height: 844)
    private let screenTraits = UITraitCollection(displayScale: 2.0)

    /// Whether to record new baselines.
    /// CI record job passes SWIFT_ACTIVE_COMPILATION_CONDITIONS=SNAPSHOT_RECORD
    /// which compiles into the test binary (env vars don't reach the simulator).
    /// Local dev: `SNAPSHOT_TESTING_RECORD=all` env var still works for native runs.
    private var isRecording: Bool {
        #if SNAPSHOT_RECORD
            return true
        #else
            return ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "all"
        #endif
    }

    /// Asserts a snapshot of a full-screen view at 390x844 pt / 2x scale.
    private func assertScreenSnapshot(
        of view: some View,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: screenLayout, traits: screenTraits),
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )
    }

    // MARK: - Setup / No Identity State

    // testSetupView, testSetupViewDark, testSetupViewGerman removed alongside
    // SetupView retirement (2026-05-03 Phase 1 of
    // 2026-05-02-ios-humble-ui-deep-retirement): the dead SetupView
    // (no production call site — onboarding routes through CoreOnboardingView
    // in ContentView, not SetupView) was deleted. Behavioral coverage of
    // identity creation lives in CoreOnboardingView's own tests + the core
    // engine's reachability walker.

    // MARK: - Onboarding

    // Onboarding screens are now rendered by core via CoreOnboardingView.
    // Snapshot tests for individual step views were removed when the custom
    // onboarding was replaced with the core-driven flow.
    // TODO: Add CoreOnboardingView snapshot once MobileOnboardingWorkflow
    // can be instantiated in the test harness.

    // MARK: - Main App Views

    func testHomeViewEmpty() {
        let vm = makeViewModel()
        let view = HomeView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testHomeViewWithFields() {
        let vm = makeViewModel(
            card: VauchiContactCard(displayName: "Alice", fields: sampleFields)
        )
        let view = HomeView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testContactsViewEmpty() {
        let vm = makeViewModel()
        let view = ContactsView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testContactsViewWithContacts() {
        let vm = makeViewModel(contacts: sampleContacts)
        let view = ContactsView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    // testSettingsView, testThemeSettingsView, testLanguageSettingsView
    // removed in the 2026-05-02 SettingsView/RecoveryView retirement
    // (_private/docs/problems/2026-04-28-pure-humble-ui-retire-native-screens/).
    // SettingsView and its sub-screens (Theme, Language, Consent, Resistance,
    // Groups, Recovery, SocialGraph) are deleted — the Settings tab routes to
    // CoreScreenView("Settings") via MoreView. Behavioral coverage lives in
    // core/vauchi-app/src/ui/settings.rs (engine tests) and the reachability
    // walker. A snapshot test against CoreScreenView would need a real
    // PlatformAppEngine seeded for the Settings screen — not available in
    // the SnapshotTest runtime.

    // testHelpView removed alongside HelpView retirement
    // (2026-05-03 Phase 1 of 2026-05-02-ios-humble-ui-deep-retirement):
    // the More tab now routes Help via `CoreScreenView(screenName: "help")`.
    // A snapshot test against CoreScreenView would need a real
    // PlatformAppEngine seeded for the Help screen — not available in
    // the SnapshotTest runtime. Behavioral coverage lives in
    // core/vauchi-app/src/ui/help.rs (engine tests) and the reachability
    // walker.

    // testLabelsView removed in the 2026-04-28 Pure Humble UI Pair 2
    // retirement: native LabelsView (a SwiftUI shadow of GroupsView)
    // and LabelDetailView were deleted; "Visibility Labels" navigation
    // now lands on GroupsView's CoreScreenView("Groups"), which would
    // need a real PlatformAppEngine seeded with labels for a snapshot.
    // Behavioral coverage lives in
    // core/vauchi-app/src/ui/group_detail.rs (engine tests) and the
    // reachability walker.

    // MARK: - Detail Views

    //
    // testContactDetailView and testDeliveryStatusView removed in the
    // 2026-04-28 Pure Humble UI retirement
    // (_private/docs/problems/2026-04-28-pure-humble-ui-retire-native-screens/).
    // Both screens now render via CoreScreenView against core's
    // ContactDetailEngine / DeliveryStatusEngine. A snapshot test against
    // CoreScreenView would need a real PlatformAppEngine seeded with the
    // contact / delivery records — not available in the SnapshotTest
    // runtime. Behavioral coverage lives in
    // core/vauchi-app/tests/reachability/contact_detail.rs and
    // core/vauchi-app/tests/reachability/delivery_status.rs.

    // testRecoveryView removed in the 2026-05-02
    // SettingsView/RecoveryView retirement — the Recovery screen now
    // renders via core's BackupRecoveryEngine.

    // MARK: - Special States

    func testLoadingView() {
        let view = LoadingView()

        assertScreenSnapshot(of: view)
    }

    func testSyncingState() {
        let vm = makeViewModel(syncState: .syncing)
        let view = HomeView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    // MARK: - Dark Mode Variants

    func testHomeViewWithFieldsDark() {
        let vm = makeViewModel(
            card: VauchiContactCard(displayName: "Alice", fields: sampleFields)
        )
        let view = HomeView()
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)

        assertScreenSnapshot(of: view)
    }

    func testContactsViewWithContactsDark() {
        let vm = makeViewModel(contacts: sampleContacts)
        let view = ContactsView()
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)

        assertScreenSnapshot(of: view)
    }

    // testSettingsViewDark removed in the 2026-05-02
    // SettingsView/RecoveryView retirement.

    // MARK: - German Locale Variants

    /// Helper to switch locale, run a snapshot, then restore.
    private func withLocale(_ code: String, view: some View, file: StaticString = #file, testName: String = #function, line: UInt = #line) {
        let previousLocale = LocalizationService.shared.currentLocale
        let wasFollowingSystem = LocalizationService.shared.followSystem
        LocalizationService.shared.selectLocale(code: code)

        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: screenLayout, traits: screenTraits),
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )

        // Restore previous locale state
        if wasFollowingSystem {
            LocalizationService.shared.resetToSystem()
        } else {
            LocalizationService.shared.selectLocale(previousLocale)
        }
    }

    func testHomeViewWithFieldsGerman() {
        let vm = makeViewModel(
            card: VauchiContactCard(displayName: "Alice", fields: sampleFields)
        )
        let view = HomeView()
            .environmentObject(vm)

        withLocale("de", view: view)
    }

    func testContactsViewWithContactsGerman() {
        let vm = makeViewModel(contacts: sampleContacts)
        let view = ContactsView()
            .environmentObject(vm)

        withLocale("de", view: view)
    }

    // testSettingsViewGerman removed in the 2026-05-02
    // SettingsView/RecoveryView retirement.
}
