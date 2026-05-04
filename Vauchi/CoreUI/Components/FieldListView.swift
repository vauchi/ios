// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// FieldListView.swift
// Renders a FieldList component from core UI

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
                        availableGroups: component.availableGroups,
                        onAction: onAction
                    )
                }
            }
        }
        .accessibilityLabel(component.a11y?.label ?? "Contact fields")
        .accessibilityHint(component.a11y?.hint ?? "")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

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
                Image(systemName: iconForFieldType(field.fieldType))
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
        let visibleGroups: [String] = {
            if case let .groups(groups) = field.visibility {
                return groups
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

    private func iconForFieldType(_ type: String) -> String {
        switch type.lowercased() {
        case "phone": "phone"
        case "email": "envelope"
        case "website": "globe"
        case "address": "mappin"
        case "social": "at"
        case "birthday": "gift"
        default: "doc.text"
        }
    }
}
