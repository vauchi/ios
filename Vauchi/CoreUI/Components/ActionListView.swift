// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ActionListView.swift
// Renders an ActionList component from core UI

import SwiftUI

/// Renders a core `Component::ActionList` as a list of tappable action rows.
struct ActionListView: View {
    let component: ActionListComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(component.items) { item in
                ActionListItemRow(item: item) {
                    onAction(.listItemSelected(componentId: component.id, itemId: item.id))
                }

                if item.id != component.items.last?.id {
                    Divider()
                        .padding(.leading, item.icon != nil ? 52 : 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ActionListItemRow: View {
    let item: ActionListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let icon = item.icon {
                    Image(systemName: sfSymbolForCoreIcon(icon))
                        .font(.system(size: 20))
                        .foregroundColor(.cyan)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }

                Text(item.label)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if let detail = item.detail {
                    Text(detail)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.a11y?.label ?? item.label)
        .accessibilityHint(item.a11y?.hint ?? item.detail ?? "")
        .accessibilityAddTraits(.isButton)
    }
}
