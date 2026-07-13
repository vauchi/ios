// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
import SwiftUI

/// Renders a core `Component::FieldList` with field rows and visibility controls.
struct FieldListView: View {
    let component: FieldListComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let fields = component.fields
        VStack(alignment: .leading, spacing: CGFloat(tokens.spacing.smMd)) {
            if fields.isEmpty {
                emptyState
            } else {
                ForEach(fields) { field in
                    FieldListRow(
                        field: field,
                        visibilityMode: component.visibilityMode,
                        onAction: onAction
                    )
                }
            }
        }
        // TODO(HUMBLE): [W, P2] default a11y label names a domain concept (`Contact fields`)
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        .accessibilityLabel(component.a11y?.label ?? "Contact fields")
        .accessibilityHint(component.a11y?.hint ?? "")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            // TODO(HUMBLE): [W, P2] hardcoded English empty-state copy leaks domain concept (`fields`)
            // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
            Text("No fields added yet")
                .font(.body)
                .foregroundColor(.secondary)

            Text("You can add fields later in your card settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct FieldListRow: View {
    let field: Field
    let visibilityMode: VisibilityMode
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack {
            Image(systemName: sfSymbolForCoreIcon(field.icon))
                .foregroundColor(.cyan)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(field.value)
                    .font(.body)
            }

            Spacer()

            visibilityControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(field.a11y?.label ?? "\(field.label): \(field.value)")
        .accessibilityHint(field.a11y?.hint ?? "")
    }

    @ViewBuilder
    private var visibilityControl: some View {
        // TODO(HUMBLE): [D/T, P1] frontend interprets `VisibilityMode` and `field.visibility` to render controls;
        // core should emit generic presentation tokens (e.g. icon_token, visibility_controls)
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        if case .showHide = visibilityMode {
            let isShown: Bool = {
                if case .shown = field.visibility { return true }
                return false
            }()

            Button {
                onAction(.fieldVisibilityChanged(
                    fieldId: field.id,
                    groupId: nil,
                    visible: !isShown
                ))
            } label: {
                Image(systemName: isShown ? "eye" : "eye.slash")
                    .foregroundColor(isShown ? .cyan : .gray)
            }
            .accessibilityLabel(isShown ? "Visible" : "Hidden")
            .accessibilityHint("Toggle field visibility")
        }
    }
}
