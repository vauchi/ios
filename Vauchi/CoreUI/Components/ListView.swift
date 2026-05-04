// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ListView.swift
// Renders a List component from core UI (Wire Humble — domain-agnostic).

import CoreUIModels
import SwiftUI

/// Renders a core `Component::List` as a searchable list of items. The
/// renderer doesn't know what kind of items it's rendering — engines
/// produce UI-shaped `Item`s from any domain (contacts, decoys, members).
struct ListView: View {
    let component: ListComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    @State private var searchQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(tokens.spacing.smMd)) {
            if component.searchable {
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .padding(CGFloat(tokens.spacing.sm))
                    .background(Color(.systemGray6))
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    .onChange(of: searchQuery) { newValue in
                        onAction(.searchChanged(componentId: component.id, query: newValue))
                    }
                    .accessibilityLabel("Search list")
            }

            VStack(spacing: 0) {
                ForEach(component.items) { item in
                    ItemRow(
                        item: item,
                        onTap: {
                            onAction(.listItemSelected(componentId: component.id, itemId: item.id))
                        },
                        onAction: { action in
                            onAction(.listItemAction(
                                componentId: component.id,
                                itemId: item.id,
                                actionId: action.id
                            ))
                        }
                    )

                    if item.id != component.items.last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

/// System SF-Symbol that represents a given list-item action kind.
/// Shared between context menu + (future) swipe-action rendering.
func systemIcon(for kind: ListItemActionKind) -> String {
    switch kind {
    case .archive: "archivebox"
    case .unarchive: "tray.and.arrow.up"
    case .hide: "eye.slash"
    case .unhide: "eye"
    case .delete: "trash"
    case .undelete: "arrow.uturn.backward"
    case .custom, .unknown: "ellipsis.circle"
    }
}

struct ItemRow: View {
    let item: Item
    let onTap: () -> Void
    let onAction: (ListItemAction) -> Void

    /// Dynamic-Type-aware avatar-initial font size, tied to `.body` so it
    /// tracks the row's general text scaling.
    @ScaledMetric(relativeTo: .body) private var avatarInitialSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            Text(item.avatarInitials)
                .font(.system(size: avatarInitialSize, weight: .semibold))
                .minimumScaleFactor(0.5)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.cyan)
                .clipShape(Circle())

            Button(action: onTap) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                            .foregroundColor(.primary)

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if let status = item.status {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.a11y?.label ?? item.name)
            .accessibilityHint(item.a11y?.hint ?? item.subtitle ?? "")
            .accessibilityAddTraits(.isButton)

            if !item.actions.isEmpty {
                Menu {
                    ForEach(item.actions) { action in
                        Button(role: action.destructive ? .destructive : nil) {
                            onAction(action)
                        } label: {
                            Label(action.label, systemImage: systemIcon(for: action.kind))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("More actions for \(item.name)")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contextMenu {
            ForEach(item.actions) { action in
                Button(role: action.destructive ? .destructive : nil) {
                    onAction(action)
                } label: {
                    Label(action.label, systemImage: systemIcon(for: action.kind))
                }
            }
        }
    }
}
