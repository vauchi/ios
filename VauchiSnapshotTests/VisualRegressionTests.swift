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

    func testSetupView() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SetupView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    // MARK: - Onboarding Steps

    func testWelcomeStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = WelcomeStepView(onContinue: {}, onRestore: {})
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testCreateIdentityStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = CreateIdentityStepView(
            displayName: .constant(""),
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testCreateIdentityStepFilled() {
        let vm = makeViewModel(hasIdentity: false)
        let view = CreateIdentityStepView(
            displayName: .constant("Alice"),
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertScreenSnapshot(of: view)
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

        assertScreenSnapshot(of: view)
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

        assertScreenSnapshot(of: view)
    }

    func testSecurityStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SecurityStepView(
            onContinue: {},
            onBack: {}
        )
        .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testReadyStep() {
        let vm = makeViewModel(hasIdentity: false)
        let view = ReadyStepView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    // MARK: - Main App Views

    func testHomeViewEmpty() {
        let vm = makeViewModel()
        let view = HomeView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testHomeViewWithFields() {
        let vm = makeViewModel(
            card: CardInfo(displayName: "Alice", fields: sampleFields)
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

    func testExchangeView() {
        let vm = makeViewModel()
        let view = ExchangeView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testSettingsView() {
        let vm = makeViewModel()
        let view = SettingsView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testHelpView() {
        let vm = makeViewModel()
        let view = HelpView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testThemeSettingsView() {
        let vm = makeViewModel()
        let view = ThemeSettingsView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testLanguageSettingsView() {
        let vm = makeViewModel()
        let view = LanguageSettingsView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testLabelsView() {
        let vm = makeViewModel()
        let view = LabelsView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
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

        assertScreenSnapshot(of: view)
    }

    func testDeliveryStatusView() {
        let vm = makeViewModel()
        let view = DeliveryStatusView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

    func testRecoveryView() {
        let vm = makeViewModel()
        let view = RecoveryView()
            .environmentObject(vm)

        assertScreenSnapshot(of: view)
    }

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

    func testSetupViewDark() {
        let vm = makeViewModel(hasIdentity: false)
        let view = SetupView()
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)

        assertScreenSnapshot(of: view)
    }

    func testHomeViewWithFieldsDark() {
        let vm = makeViewModel(
            card: CardInfo(displayName: "Alice", fields: sampleFields)
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

    func testSettingsViewDark() {
        let vm = makeViewModel()
        let view = SettingsView()
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)

        assertScreenSnapshot(of: view)
    }

    func testExchangeViewDark() {
        let vm = makeViewModel()
        let view = ExchangeView()
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)

        assertScreenSnapshot(of: view)
    }

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
