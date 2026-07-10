// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VisualRegressionTests.swift
// Snapshot tests for all SwiftUI views
// Based on: VRT implementation plan Phase 2

import CoreUIModels
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
    // (no production call site — onboarding routes through the shared
    // `CoreScreenView` in ContentView, not SetupView) was deleted.
    // Behavioral coverage of identity creation lives in the core
    // engine's reachability walker.

    // MARK: - Onboarding

    // Onboarding screens are now rendered by core via the shared
    // `CoreScreenView` (PAE). Snapshot tests for individual step views
    // were removed when the custom onboarding was replaced with the
    // core-driven flow. A snapshot can be added by injecting a
    // `VauchiViewModel` whose `coreViewModel` is on an Onboarding
    // screen. Tracked in slice 32c follow-ups.

    // MARK: - Main App Views

    func testHomeViewEmpty() {
        let vm = makeViewModel()
        let view = CoreScreenView(actionId: "my_info")
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testContactsViewEmpty() {
        let vm = makeViewModel()
        let view = CoreScreenView(actionId: "contacts")
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    // MARK: - Exchange (multi-stage QR) compact-viewport regression

    /// Regression for the iPhone-SE QR collapse. On the non-scrolling
    /// `multi_stage_exchange` screen (`ScreenLayout.fixed`) the display QR and
    /// the scan camera must SHARE the compact viewport. Before the
    /// `ResponsiveSquare` fix the rigid 250 pt camera kept its full size and
    /// starved the flexible `scaledToFit` QR, whose card `.cornerRadius` clip
    /// then shrank it to a ~9 pt sliver the peer could not scan. Rendered at
    /// iPhone-SE logical size (375×667) so the height pressure is reproduced
    /// regardless of the host simulator. The simulator has no camera, so the
    /// scan square shows the deterministic "Camera unavailable" placeholder;
    /// the baseline guards that the display QR stays large (both squares
    /// co-sized), not collapsed.
    func testMultiStageExchangeCompactViewport() {
        let vm = makeViewModel()
        let screen = ScreenModel(
            screenId: "multi_stage_exchange",
            title: "Exchange",
            components: [
                .qrCode(QrCodeComponent(
                    id: "own_qr",
                    data: "VAUCHI:snapshot-test-payload-0123456789abcdef",
                    mode: .display,
                    label: "Show this to your contact"
                )),
                .qrCode(QrCodeComponent(
                    id: "peer_scan",
                    data: "",
                    mode: .scan,
                    label: "Scan their code"
                )),
            ],
            actions: [],
            layout: .fixed
        )
        let view = ScreenRendererView(screen: screen, onAction: { _ in })
            .environmentObject(vm)

        assertSnapshot(
            of: view,
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 667),
                traits: UITraitCollection(displayScale: 2.0)
            ),
            record: isRecording
        )
    }

    // MARK: - Glance (scroll-layout) QR display regression

    /// The BLE-Glance screen (`exchange_ble_glance`) is `ScreenLayout.scroll`,
    /// so its components render inside a ScrollView, which proposes nil
    /// height. The old GeometryReader-based `ResponsiveSquare` collapsed to
    /// its ~10 pt ideal under that proposal — an icon-sized, unscannable QR
    /// (device-confirmed 2026-07-02, iPhone SE;
    /// `2026-07-02-ios-qr-display-collapses-in-scroll-layout`). The baseline
    /// guards a near full-width QR in a scroll context; the fixed-layout
    /// sibling above guards the definite-height context — both proposals
    /// must keep rendering large.
    func testGlanceScrollLayoutQrDisplayStaysLarge() {
        let vm = makeViewModel()
        let screen = ScreenModel(
            screenId: "exchange_ble_glance",
            title: "Glance",
            components: [
                .qrCode(QrCodeComponent(
                    id: "own_qr",
                    data: "VAUCHI:snapshot-test-payload-0123456789abcdef",
                    mode: .display,
                    label: "Show this to exchange"
                )),
            ],
            actions: [],
            layout: .scroll
        )
        let view = ScreenRendererView(screen: screen, onAction: { _ in })
            .environmentObject(vm)

        assertSnapshot(
            of: view,
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 375, height: 667),
                traits: UITraitCollection(displayScale: 2.0)
            ),
            record: isRecording
        )
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
        let view = CoreScreenView(actionId: "my_info")
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    // MARK: - Dark Mode Variants

    func testHomeViewDark() {
        let vm = makeViewModel()
        let view = CoreScreenView(actionId: "my_info")
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)

        assertScreenSnapshot(of: view)
    }

    func testContactsViewDark() {
        let vm = makeViewModel()
        let view = CoreScreenView(actionId: "contacts")
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

    func testHomeViewGerman() {
        let vm = makeViewModel()
        let view = CoreScreenView(actionId: "my_info")
            .environmentObject(vm)

        withLocale("de", view: view)
    }

    func testContactsViewGerman() {
        let vm = makeViewModel()
        let view = CoreScreenView(actionId: "contacts")
            .environmentObject(vm)

        withLocale("de", view: view)
    }

    // testSettingsViewGerman removed in the 2026-05-02
    // SettingsView/RecoveryView retirement.
}
