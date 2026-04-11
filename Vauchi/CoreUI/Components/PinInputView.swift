// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// PinInputView.swift
// Renders a PinInput component from core UI

import SwiftUI

/// Renders a core `Component::PinInput` as a PIN entry field.
struct PinInputView: View {
    let component: PinInputComponent
    let onAction: (UserAction) -> Void

    @State private var localValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(component.label)
                .font(.headline)
                .foregroundColor(.secondary)

            Group {
                if component.masked {
                    SecureField("", text: $localValue)
                } else {
                    TextField("", text: $localValue)
                }
            }
            .textFieldStyle(.plain)
            .font(.title3.monospaced())
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .keyboardType(.numberPad)
            .onChange(of: localValue) { newValue in
                let value: String
                if newValue.count > component.length {
                    value = String(newValue.prefix(component.length))
                    localValue = value
                } else {
                    value = newValue
                }
                onAction(.textChanged(componentId: component.id, value: value))
            }
            .accessibilityLabel(component.a11y?.label ?? component.label)
            .accessibilityHint(component.a11y?.hint ?? "")

            if let error = component.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }
}
