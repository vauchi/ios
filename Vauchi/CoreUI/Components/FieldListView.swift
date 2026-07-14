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
        VStack(alignment: .leading, spacing: CGFloat(tokens.spacing.smMd)) {
            if component.fields.isEmpty {
                emptyState
            } else {
                ForEach(component.fields) { field in
                    FieldListRow(
                        field: field,
                        visibilityMode: component.visibilityMode,
                        availableGroups: component.availableScopes,
                        onAction: onAction
                    )
                }
            }
        }
        .accessibilityLabel(component.a11y?.label ?? component.title)
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
    let availableGroups: [String]
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if case .perGroup = visibilityMode, !availableGroups.isEmpty {
                groupChips
            }
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

    private var groupChips: some View {
        // TODO(HUMBLE): [D/T, P1] frontend maps per-group visibility state and group names to UI;
        // core should supply generic chips with explicit action_ids and labels
        // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
        let visibleGroups: [String] = {
            if case let .scopes(scopes) = field.visibility {
                return scopes
            }
            return []
        }()

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableGroups, id: \.self) { group in
                    let isVisible = visibleGroups.contains(group)
                    Button {
                        onAction(.fieldVisibilityChanged(
                            fieldId: field.id,
                            groupId: group,
                            visible: !isVisible
                        ))
                    } label: {
                        Text(group)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isVisible ? Color.cyan.opacity(0.2) : Color(.systemGray5))
                            .foregroundColor(isVisible ? .cyan : .secondary)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("\(group): \(isVisible ? "visible" : "hidden")")
                }
            }
        }
    }
}
