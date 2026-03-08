// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactListView.swift
// Renders a ContactList component from core UI

import SwiftUI

/// Renders a core `Component::ContactList` as a searchable list of contacts.
struct ContactListView: View {
    let component: ContactListComponent
    let onAction: (UserAction) -> Void

    @State private var searchQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if component.searchable {
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .onChange(of: searchQuery) { newValue in
                        onAction(.searchChanged(componentId: component.id, query: newValue))
                    }
                    .accessibilityLabel("Search contacts")
            }

            VStack(spacing: 0) {
                ForEach(component.contacts) { contact in
                    ContactItemRow(contact: contact) {
                        onAction(.listItemSelected(componentId: component.id, itemId: contact.id))
                    }

                    if contact.id != component.contacts.last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

struct ContactItemRow: View {
    let contact: ContactItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar circle with initials
                Text(contact.avatarInitials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.cyan)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    if let subtitle = contact.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let status = contact.status {
                    Text(status)
                        .font(.caption)
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
        .accessibilityLabel(contact.name)
        .accessibilityHint(contact.subtitle ?? "")
        .accessibilityAddTraits(.isButton)
    }
}
