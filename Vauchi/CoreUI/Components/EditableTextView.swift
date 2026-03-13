// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// EditableTextView.swift
// Renders an EditableText component from core UI (iOS)

import SwiftUI

/// Renders a core `Component::EditableText` that toggles between display and edit mode.
struct EditableTextView: View {
    let component: EditableTextComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(component.label)
                .font(.caption)
                .foregroundColor(.secondary)

            if component.editing {
                TextField(component.label, text: .constant(component.value))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: component.value) { _, newValue in
                        onAction(.textChanged(componentId: component.id, value: newValue))
                    }

                if let error = component.validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else {
                HStack {
                    Text(component.value)
                        .font(.body)

                    Spacer()

                    Button {
                        onAction(.actionPressed(actionId: "\(component.id):edit"))
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(component.label)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
