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
/// Uses swift-snapshot-testing to capture reference images and compare
/// against baselines. Run with `--update-snapshots` to regenerate baselines.
///
/// Device: iPhone 13 Pro logical size (390×844 pt) rendered at 2x scale.
/// IMPORTANT: Must run on a 2x simulator (e.g. iPhone SE 3) for baselines to match.
/// Renders at 780×1688 px — large enough to catch layout issues,
/// small enough to keep baselines under 80 KB each (~45% smaller than 3x).
@MainActor
final class VisualRegressionTests: XCTestCase {
    /// Consistent device for all snapshots.
    /// Uses 2x scale instead of 3x to reduce baseline image size while
    /// preserving the same logical layout (390×844 pt).
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 390, height: 844),
        traits: UITraitCollection(displayScale: 2.0)
    )

    /// Whether to record new baselines.
    /// CI (no env var) → false → comparison mode.
    /// Local dev (`SNAPSHOT_TESTING_RECORD=all xcodebuild test`) → true → recording mode.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "all"
    }

    // setUp intentionally removed — no custom setup needed

    // MARK: - Setup / No Identity State

    func testSetupView() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SetupView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    // MARK: - Onboarding Steps

    func testWelcomeStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = WelcomeStepView(onContinue: {}, onRestore: {})
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testCreateIdentityStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = CreateIdentityStepView(
            displayName: .constant(""),
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testCreateIdentityStepFilled() {
        let vm = makeViewModel(hasIdentity: false)
        let view = CreateIdentityStepView(
            displayName: .constant("Alice"),
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testAddFieldsStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = AddFieldsStepView(
            phone: .constant(""),
            email: .constant(""),
            onContinue: {},
            onBack: {},
            onSkip: {}
        )
        .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testPreviewCardStep() {
        let data = OnboardingData()
        data.displayName = "Alice"
        data.email = "alice@example.com"
        data.phone = "+41 79 123 45 67"

        let vm = makeViewModel(hasIdentity: false)
        let view = PreviewCardStepView(
            onboardingData: data,
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testSecurityStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SecurityStepView(
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testReadyStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = ReadyStepView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    // MARK: - Main App Views

    func testHomeViewEmpty() {
        let vm = makeViewModel()
        let view = HomeView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testHomeViewWithFields() {
        let vm = makeViewModel(
            card: CardInfo(displayName: "Alice", fields: sampleFields)
        )
        let view = HomeView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testContactsViewEmpty() {
        let vm = makeViewModel()
        let view = ContactsView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testContactsViewWithContacts() {
        let vm = makeViewModel(contacts: sampleContacts)
        let view = ContactsView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testExchangeView() {
        let vm = makeViewModel()
        let view = ExchangeView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testSettingsView() {
        let vm = makeViewModel()
        let view = SettingsView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testHelpView() {
        let vm = makeViewModel()
        let view = HelpView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testThemeSettingsView() {
        let vm = makeViewModel()
        let view = ThemeSettingsView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testLanguageSettingsView() {
        let vm = makeViewModel()
        let view = LanguageSettingsView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testLabelsView() {
        let vm = makeViewModel()
        let view = LabelsView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    // MARK: - Detail Views

    func testContactDetailView() {
        let contact = ContactInfo(
            id: "c1",
            displayName: "Bob",
            verified: true,
            card: CardInfo(displayName: "Bob", fields: [
                FieldInfo(id: "bf1", fieldType: "email", label: "Work", value: "bob@work.com"),
                FieldInfo(id: "bf2", fieldType: "phone", label: "Mobile", value: "+41 78 987 65 43"),
            ]),
            addedAt: Date()
        )
        let vm = makeViewModel(contacts: [contact])
        let view = ContactDetailView(contact: contact)
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testDeliveryStatusView() {
        let vm = makeViewModel()
        let view = DeliveryStatusView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testRecoveryView() {
        let vm = makeViewModel()
        let view = RecoveryView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    // MARK: - Special States

    func testLoadingView() {
        let view = LoadingView()

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testSyncingState() {
        let vm = makeViewModel(syncState: .syncing)
        let view = HomeView()
            .environmentObject(vm)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
            record: isRecording
        )
    }

    // MARK: - Dark Mode Variants

    /// Helper to create a hosting controller with dark mode forced.
    private func darkController<V: View>(_ view: V) -> UIHostingController<V> {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        return controller
    }

    func testSetupViewDark() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SetupView()
            .environmentObject(vm)

        assertSnapshot(
            of: darkController(view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testHomeViewWithFieldsDark() {
        let vm = makeViewModel(
            card: CardInfo(displayName: "Alice", fields: sampleFields)
        )
        let view = HomeView()
            .environmentObject(vm)

        assertSnapshot(
            of: darkController(view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testContactsViewWithContactsDark() {
        let vm = makeViewModel(contacts: sampleContacts)
        let view = ContactsView()
            .environmentObject(vm)

        assertSnapshot(
            of: darkController(view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testSettingsViewDark() {
        let vm = makeViewModel()
        let view = SettingsView()
            .environmentObject(vm)

        assertSnapshot(
            of: darkController(view),
            as: .image(on: device),
            record: isRecording
        )
    }

    func testExchangeViewDark() {
        let vm = makeViewModel()
        let view = ExchangeView()
            .environmentObject(vm)

        assertSnapshot(
            of: darkController(view),
            as: .image(on: device),
            record: isRecording
        )
    }

    // MARK: - German Locale Variants

    /// Helper to switch locale, run a snapshot, then restore.
    private func withLocale(_ code: String, view: some View, file: StaticString = #file, testName: String = #function, line: UInt = #line) {
        let previousLocale = LocalizationService.shared.currentLocale
        let wasFollowingSystem = LocalizationService.shared.followSystem
        LocalizationService.shared.selectLocale(code: code)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: device),
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

    func testSetupViewGerman() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SetupView()
            .environmentObject(vm)

        withLocale("de", view: view)
    }

    func testHomeViewWithFieldsGerman() {
        let vm = makeViewModel(
            card: CardInfo(displayName: "Alice", fields: sampleFields)
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

    func testSettingsViewGerman() {
        let vm = makeViewModel()
        let view = SettingsView()
            .environmentObject(vm)

        withLocale("de", view: view)
    }

    func testExchangeViewGerman() {
        let vm = makeViewModel()
        let view = ExchangeView()
            .environmentObject(vm)

        withLocale("de", view: view)
    }
}
