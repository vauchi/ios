// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// TextInputView.swift
// Renders a TextInput component from core UI

import CoreUIModels
import SwiftUI

/// Renders a core `Component::TextInput` as a styled TextField with validation.
struct TextInputView: View {
    let component: TextInputComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    @State private var localValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(tokens.spacing.sm)) {
            Text(component.label)
                .font(.headline)
                .foregroundColor(.secondary)

            TextField(
                component.placeholder ?? component.label,
                text: $localValue
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            .keyboardType(keyboardType(for: component.inputType))
            .autocapitalization(autocapitalization(for: component.inputType))
            .onChange(of: localValue) { newValue in
                let value: String
                if let maxLen = component.maxLength, newValue.count > maxLen {
                    value = String(newValue.prefix(maxLen))
                    localValue = value
                } else {
                    value = newValue
                }
                onAction(.textChanged(componentId: component.id, value: value))
            }
            .accessibilityIdentifier(component.id)
            .accessibilityLabel(component.a11y?.label ?? component.label)
            .accessibilityHint(component.a11y?.hint ?? component.placeholder ?? "")

            if let error = component.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .onAppear {
            localValue = component.value
        }
        // Track core-driven value changes (e.g. submit_custom_group resets
        // the field to empty in the ScreenModel — Humble UI principle:
        // never desync from core state).
        .onChange(of: component.value) { newValue in
            if newValue != localValue {
                localValue = newValue
            }
        }
    }

    private func keyboardType(for inputType: InputType) -> UIKeyboardType {
        switch inputType {
        case .text: .default
        case .phone: .phonePad
        case .email: .emailAddress
        case .password: .default
        }
    }

    private func autocapitalization(for inputType: InputType) -> UITextAutocapitalizationType {
        switch inputType {
        case .text: .words
        case .phone, .email, .password: .none
        }
    }
}
