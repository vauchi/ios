// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SettingsGroupView.swift
// Renders a SettingsGroup component from core UI

import SwiftUI

/// Renders a core `Component::SettingsGroup` as a grouped list of settings items.
struct SettingsGroupView: View {
    let component: SettingsGroupComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(tokens.spacing.smMd)) {
            Text(component.label)
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(component.items) { item in
                    SettingsItemRow(
                        item: item,
                        componentId: component.id,
                        onAction: onAction
                    )

                    if item.id != component.items.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

struct SettingsItemRow: View {
    let item: SettingsItem
    let componentId: String
    let onAction: (UserAction) -> Void

    var body: some View {
        switch item.kind {
        case let .toggle(enabled):
            toggleRow(enabled: enabled)

        case let .value(value):
            valueRow(value: value)

        case let .link(detail):
            linkRow(detail: detail)

        case let .destructive(label):
            destructiveRow(label: label)

        case .unknown:
            EmptyView()
        }
    }

    private func toggleRow(enabled: Bool) -> some View {
        HStack {
            Text(item.label)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { _ in
                    onAction(.settingsToggled(componentId: componentId, itemId: item.id))
                }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.a11y?.label ?? item.label)
        .accessibilityHint(item.a11y?.hint ?? "")
        .accessibilityValue(enabled ? "On" : "Off")
    }

    private func valueRow(value: String) -> some View {
        HStack {
            Text(item.label)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.a11y?.label ?? "\(item.label): \(value)")
        .accessibilityHint(item.a11y?.hint ?? "")
    }

    private func linkRow(detail: String?) -> some View {
        Button {
            onAction(.listItemSelected(componentId: componentId, itemId: item.id))
        } label: {
            HStack {
                Text(item.label)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if let detail {
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
        .accessibilityHint(item.a11y?.hint ?? detail ?? "")
        .accessibilityAddTraits(.isButton)
    }

    private func destructiveRow(label: String) -> some View {
        Button {
            onAction(.listItemSelected(componentId: componentId, itemId: item.id))
        } label: {
            HStack {
                Text(label)
                    .font(.body)
                    .foregroundColor(.red)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.a11y?.label ?? label)
        .accessibilityHint(item.a11y?.hint ?? "")
        .accessibilityAddTraits(.isButton)
    }
}
