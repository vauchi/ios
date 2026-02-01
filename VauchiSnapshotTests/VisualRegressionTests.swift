// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// VisualRegressionTests.swift
// Snapshot tests for all SwiftUI views
// Based on: VRT implementation plan Phase 2

import SnapshotTesting
import SwiftUI
import XCTest
@testable import Vauchi

/// Visual regression tests for all major views.
///
/// Uses swift-snapshot-testing to capture reference images and compare
/// against baselines. Run with `--update-snapshots` to regenerate baselines.
///
/// Device: iPhone 15 Pro (393×852 pt)
@MainActor
final class VisualRegressionTests: XCTestCase {
    // Use a consistent device for all snapshots
    private let device: ViewImageConfig = .iPhone13Pro
    // Set to true when generating initial baselines or updating after intentional changes
    // In CI, this should always be false (default)
    private var isRecording: Bool { false }

    override func setUp() {
        super.setUp()
        // Ensure consistent rendering
        // isRecording can be toggled via environment variable in CI if needed
    }

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
}
