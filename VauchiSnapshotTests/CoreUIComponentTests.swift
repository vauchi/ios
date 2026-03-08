// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CoreUIComponentTests.swift
// Component-level snapshot tests for CoreUI views in isolation.
// Uses smaller fixed-size layouts (390×200 pt) instead of full-screen device configs.

import SnapshotTesting
import SwiftUI
@testable import Vauchi
import XCTest

/// Snapshot tests for individual CoreUI components rendered in isolation.
///
/// Each component is tested with mock data at a compact size (390 pt wide)
/// to verify visual rendering without full-screen context.
/// Rendered at 2x scale to match existing VRT baselines.
@MainActor
final class CoreUIComponentTests: XCTestCase {
    /// Whether to record new baselines. Always false in CI.
    private var isRecording: Bool {
        false
    }

    /// No-op action handler for components that require one.
    private let noOp: (UserAction) -> Void = { _ in }

    // MARK: - Snapshot Helpers

    /// Asserts a snapshot of a view at a fixed width with automatic height.
    private func assertComponentSnapshot(
        of view: some View,
        width: CGFloat = 390,
        height: CGFloat = 200,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: view.padding(),
            as: .image(
                layout: .fixed(width: width, height: height),
                traits: UITraitCollection(displayScale: 2.0)
            ),
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )
    }

    // MARK: - TextInputView

    func testTextInputEmpty() {
        let component = TextInputComponent(
            id: "name",
            label: "Display Name",
            value: "",
            placeholder: "Enter your name",
            maxLength: 50,
            validationError: nil,
            inputType: .text
        )
        let view = TextInputView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view)
    }

    func testTextInputWithValue() {
        let component = TextInputComponent(
            id: "name",
            label: "Display Name",
            value: "Alice",
            placeholder: "Enter your name",
            maxLength: 50,
            validationError: nil,
            inputType: .text
        )
        let view = TextInputView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view)
    }

    func testTextInputWithValidationError() {
        let component = TextInputComponent(
            id: "name",
            label: "Display Name",
            value: "",
            placeholder: "Enter your name",
            maxLength: 50,
            validationError: "Name is required",
            inputType: .text
        )
        let view = TextInputView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view)
    }

    func testTextInputEmailType() {
        let component = TextInputComponent(
            id: "email",
            label: "Email",
            value: "alice@example.com",
            placeholder: "you@example.com",
            maxLength: nil,
            validationError: nil,
            inputType: .email
        )
        let view = TextInputView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view)
    }

    func testTextInputPhoneType() {
        let component = TextInputComponent(
            id: "phone",
            label: "Phone",
            value: "+41 79 123 45 67",
            placeholder: "+41...",
            maxLength: nil,
            validationError: nil,
            inputType: .phone
        )
        let view = TextInputView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view)
    }

    // MARK: - ToggleListView

    func testToggleListDefault() {
        let component = ToggleListComponent(
            id: "groups",
            label: "Groups",
            items: [
                ToggleItem(id: "family", label: "Family", selected: true, subtitle: nil),
                ToggleItem(id: "friends", label: "Friends", selected: false, subtitle: nil),
                ToggleItem(id: "coworkers", label: "Coworkers", selected: false, subtitle: nil),
            ]
        )
        let view = ToggleListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 250)
    }

    func testToggleListAllSelected() {
        let component = ToggleListComponent(
            id: "groups",
            label: "Groups",
            items: [
                ToggleItem(id: "family", label: "Family", selected: true, subtitle: "Close relatives"),
                ToggleItem(id: "friends", label: "Friends", selected: true, subtitle: "Personal contacts"),
                ToggleItem(id: "coworkers", label: "Coworkers", selected: true, subtitle: "Work contacts"),
            ]
        )
        let view = ToggleListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 300)
    }

    func testToggleListSingleItem() {
        let component = ToggleListComponent(
            id: "groups",
            label: "Groups",
            items: [
                ToggleItem(id: "business", label: "Business", selected: false, subtitle: "Professional contacts"),
            ]
        )
        let view = ToggleListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 150)
    }

    // MARK: - FieldListView

    func testFieldListEmpty() {
        let component = FieldListComponent(
            id: "fields",
            fields: [],
            visibilityMode: .showHide,
            availableGroups: []
        )
        let view = FieldListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view)
    }

    func testFieldListWithFieldsShowHide() {
        let component = FieldListComponent(
            id: "fields",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .hidden),
            ],
            visibilityMode: .showHide,
            availableGroups: []
        )
        let view = FieldListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 250)
    }

    func testFieldListWithFieldsPerGroup() {
        let component = FieldListComponent(
            id: "fields",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .groups(["Family", "Friends"])),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .groups(["Family"])),
            ],
            visibilityMode: .perGroup,
            availableGroups: ["Family", "Friends", "Coworkers"]
        )
        let view = FieldListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 350)
    }

    func testFieldListMultipleFieldTypes() {
        let component = FieldListComponent(
            id: "fields",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Work Email", value: "alice@work.com", visibility: .shown),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .shown),
                FieldDisplay(id: "f3", fieldType: "website", label: "Website", value: "https://alice.example.com", visibility: .shown),
                FieldDisplay(id: "f4", fieldType: "address", label: "Office", value: "Bahnhofstrasse 1, Zurich", visibility: .hidden),
            ],
            visibilityMode: .showHide,
            availableGroups: []
        )
        let view = FieldListView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 450)
    }

    // MARK: - CardPreviewView

    func testCardPreviewMinimal() {
        let component = CardPreviewComponent(
            name: "Alice",
            fields: [],
            groupViews: [],
            selectedGroup: nil
        )
        let view = CardPreviewView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 300)
    }

    func testCardPreviewWithFields() {
        let component = CardPreviewComponent(
            name: "Alice",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .shown),
            ],
            groupViews: [],
            selectedGroup: nil
        )
        let view = CardPreviewView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 400)
    }

    func testCardPreviewWithGroups() {
        let component = CardPreviewComponent(
            name: "Alice",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .groups(["Family", "Friends"])),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .groups(["Family"])),
            ],
            groupViews: [
                GroupCardView(
                    groupName: "Family",
                    displayName: "Alice",
                    visibleFields: [
                        FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                        FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .shown),
                    ]
                ),
                GroupCardView(
                    groupName: "Friends",
                    displayName: "Ali",
                    visibleFields: [
                        FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                    ]
                ),
            ],
            selectedGroup: nil
        )
        let view = CardPreviewView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 450)
    }

    func testCardPreviewGroupSelected() {
        let component = CardPreviewComponent(
            name: "Alice",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .groups(["Friends"])),
            ],
            groupViews: [
                GroupCardView(
                    groupName: "Friends",
                    displayName: "Ali",
                    visibleFields: [
                        FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                    ]
                ),
            ],
            selectedGroup: "Friends"
        )
        let view = CardPreviewView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 400)
    }

    func testCardPreviewNoVisibleFields() {
        let component = CardPreviewComponent(
            name: "Alice",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .hidden),
            ],
            groupViews: [],
            selectedGroup: nil
        )
        let view = CardPreviewView(component: component, onAction: noOp)
        assertComponentSnapshot(of: view, height: 300)
    }

    // MARK: - InfoPanelView

    func testInfoPanelWithIcon() {
        let component = InfoPanelComponent(
            id: "security",
            icon: "lock",
            title: "End-to-End Encryption",
            items: [
                InfoItem(icon: "key", title: "Your Keys", detail: "Keys are generated on your device and never leave it."),
                InfoItem(icon: "shield", title: "Zero Knowledge", detail: "The relay server cannot read your contact data."),
            ]
        )
        let view = InfoPanelView(component: component)
        assertComponentSnapshot(of: view, height: 250)
    }

    func testInfoPanelWithoutIcon() {
        let component = InfoPanelComponent(
            id: "info",
            icon: nil,
            title: "How It Works",
            items: [
                InfoItem(icon: nil, title: "Step 1", detail: "Create your identity and add contact fields."),
                InfoItem(icon: nil, title: "Step 2", detail: "Exchange cards in person via QR code."),
                InfoItem(icon: nil, title: "Step 3", detail: "Updates are delivered automatically."),
            ]
        )
        let view = InfoPanelView(component: component)
        assertComponentSnapshot(of: view, height: 300)
    }

    func testInfoPanelSingleItem() {
        let component = InfoPanelComponent(
            id: "tip",
            icon: "check",
            title: "All Set",
            items: [
                InfoItem(icon: "check", title: "Ready", detail: "Your card is ready to share."),
            ]
        )
        let view = InfoPanelView(component: component)
        assertComponentSnapshot(of: view, height: 150)
    }

    // MARK: - TextComponentView

    func testTextComponentTitle() {
        let component = TextComponent(id: "t1", content: "Welcome to Vauchi", style: .title)
        let view = TextComponentView(component: component)
        assertComponentSnapshot(of: view, height: 80)
    }

    func testTextComponentSubtitle() {
        let component = TextComponent(id: "t2", content: "Your privacy-first contact card", style: .subtitle)
        let view = TextComponentView(component: component)
        assertComponentSnapshot(of: view, height: 80)
    }

    func testTextComponentBody() {
        let component = TextComponent(
            id: "t3",
            content: "Vauchi lets you share contact information securely. Updates are end-to-end encrypted and delivered automatically.",
            style: .body
        )
        let view = TextComponentView(component: component)
        assertComponentSnapshot(of: view, height: 120)
    }

    func testTextComponentCaption() {
        let component = TextComponent(id: "t4", content: "All data stays on your device", style: .caption)
        let view = TextComponentView(component: component)
        assertComponentSnapshot(of: view, height: 60)
    }

    // MARK: - Dark Mode Variants

    /// Asserts a dark mode snapshot of a view.
    private func assertDarkSnapshot(
        of view: some View,
        width: CGFloat = 390,
        height: CGFloat = 200,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: view.padding().environment(\.colorScheme, .dark),
            as: .image(
                layout: .fixed(width: width, height: height),
                traits: UITraitCollection(displayScale: 2.0)
            ),
            record: isRecording,
            file: file,
            testName: testName,
            line: line
        )
    }

    func testTextInputDark() {
        let component = TextInputComponent(
            id: "name",
            label: "Display Name",
            value: "Alice",
            placeholder: "Enter your name",
            maxLength: 50,
            validationError: nil,
            inputType: .text
        )
        assertDarkSnapshot(of: TextInputView(component: component, onAction: noOp))
    }

    func testToggleListDark() {
        let component = ToggleListComponent(
            id: "groups",
            label: "Groups",
            items: [
                ToggleItem(id: "family", label: "Family", selected: true, subtitle: nil),
                ToggleItem(id: "friends", label: "Friends", selected: false, subtitle: "Personal contacts"),
            ]
        )
        assertDarkSnapshot(of: ToggleListView(component: component, onAction: noOp), height: 220)
    }

    func testCardPreviewDark() {
        let component = CardPreviewComponent(
            name: "Alice",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .shown),
            ],
            groupViews: [],
            selectedGroup: nil
        )
        assertDarkSnapshot(of: CardPreviewView(component: component, onAction: noOp), height: 400)
    }

    func testInfoPanelDark() {
        let component = InfoPanelComponent(
            id: "security",
            icon: "lock",
            title: "End-to-End Encryption",
            items: [
                InfoItem(icon: "key", title: "Your Keys", detail: "Keys are generated on your device and never leave it."),
                InfoItem(icon: "shield", title: "Zero Knowledge", detail: "The relay server cannot read your contact data."),
            ]
        )
        assertDarkSnapshot(of: InfoPanelView(component: component), height: 250)
    }

    func testFieldListDark() {
        let component = FieldListComponent(
            id: "fields",
            fields: [
                FieldDisplay(id: "f1", fieldType: "email", label: "Email", value: "alice@example.com", visibility: .shown),
                FieldDisplay(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67", visibility: .hidden),
            ],
            visibilityMode: .showHide,
            availableGroups: []
        )
        assertDarkSnapshot(of: FieldListView(component: component, onAction: noOp), height: 250)
    }
}
