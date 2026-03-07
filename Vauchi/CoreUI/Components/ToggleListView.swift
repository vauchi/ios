// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ToggleListView.swift
// Renders a ToggleList component from core UI

import SwiftUI

/// Renders a core `Component::ToggleList` as a list of toggleable items.
struct ToggleListView: View {
    let component: ToggleListComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(component.label)
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(component.items) { item in
                    ToggleItemRow(item: item) {
                        onAction(.itemToggled(componentId: component.id, itemId: item.id))
                    }

                    if item.id != component.items.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

struct ToggleItemRow: View {
    let item: ToggleItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.body)
                        .foregroundColor(.primary)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.selected ? .cyan : .gray)
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
    }
}
