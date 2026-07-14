// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
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
                TextField(
                    component.label,
                    text: Binding(
                        get: { component.value },
                        set: { onAction(.textChanged(componentId: component.id, value: $0)) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button(component.cancelText) {
                        onAction(.actionPressed(actionId: component.cancelActionId))
                    }
                    .buttonStyle(.bordered)

                    Button(component.saveText) {
                        onAction(.actionPressed(actionId: component.saveActionId))
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = component.validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(ThemeService.shared.error)
                }
            } else {
                HStack {
                    Text(component.value)
                        .font(.body)

                    Spacer()

                    Button {
                        onAction(.actionPressed(actionId: component.editActionId))
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(component.editText)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(component.a11y?.label ?? component.label)
        .accessibilityHint(component.a11y?.hint ?? "")
    }
}
