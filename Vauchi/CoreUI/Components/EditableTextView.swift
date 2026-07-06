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
                TextField(component.label, text: .constant(component.value))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: component.value) { newValue in
                        onAction(.textChanged(componentId: component.id, value: newValue))
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
                        // TODO(HUMBLE): [T, P1] frontend mints an edit action id from the component id;
                        // core should supply explicit `edit_action_id` (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                        onAction(.actionPressed(actionId: "\(component.id):edit"))
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    // TODO(HUMBLE): [W, P2] hardcoded English a11y label embeds an edit action role
                    // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                    .accessibilityLabel("Edit \(component.label)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(component.a11y?.label ?? component.label)
        .accessibilityHint(component.a11y?.hint ?? "")
    }
}
