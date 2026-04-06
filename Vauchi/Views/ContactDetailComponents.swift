// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactDetailComponents.swift
// Reusable subviews for ContactDetailView

import SwiftUI
import VauchiPlatform

struct ContactFieldRow: View {
    let field: FieldInfo
    var contactId: String = ""

    private func icon(for type: String) -> String {
        switch type.lowercased() {
        case "email": "envelope"
        case "phone": "phone"
        case "website": "globe"
        case "address": "house"
        case "social": "at"
        default: "note.text"
        }
    }

    private var fieldType: VauchiFieldType {
        VauchiFieldType(rawValue: field.fieldType) ?? .custom
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: field.fieldType))
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(field.fieldType.capitalized) field: \(field.label), \(field.value)")

            Spacer()

            // Quick action buttons using ContactActions
            if fieldType == .email {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .email)
                }) {
                    Image(systemName: "envelope.circle")
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Send email")
                .accessibilityHint("Opens email app to compose message to \(field.value)")
            } else if fieldType == .phone {
                HStack(spacing: 8) {
                    Button(action: {
                        ContactActions.openField(value: field.value, type: .phone)
                    }) {
                        Image(systemName: "phone.circle")
                            .foregroundColor(.green)
                    }
                    .accessibilityLabel("Call")
                    .accessibilityHint("Starts phone call to \(field.value)")
                    Button(action: {
                        if let url = ContactActions.buildSmsUrl(for: field.value) {
                            ContactActions.openUrl(url)
                        }
                    }) {
                        Image(systemName: "message.circle")
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Send SMS")
                    .accessibilityHint("Opens messages app to send SMS to \(field.value)")
                }
            } else if fieldType == .website {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .website)
                }) {
                    Image(systemName: "safari")
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Open website")
                .accessibilityHint("Opens \(field.value) in Safari")
            } else if fieldType == .address {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .address)
                }) {
                    Image(systemName: "map")
                        .foregroundColor(.orange)
                }
                .accessibilityLabel("Open in maps")
                .accessibilityHint("Opens \(field.value) in Maps app")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .contextMenu {
            // Context menu with all available actions
            Button(action: {
                ContactActions.copyToClipboard(field.value)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if fieldType == .phone {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .phone)
                }) {
                    Label("Call", systemImage: "phone")
                }
                Button(action: {
                    if let url = ContactActions.buildSmsUrl(for: field.value) {
                        ContactActions.openUrl(url)
                    }
                }) {
                    Label("Send SMS", systemImage: "message")
                }
            } else if fieldType == .email {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .email)
                }) {
                    Label("Send Email", systemImage: "envelope")
                }
            } else if fieldType == .website {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .website)
                }) {
                    Label("Open in Browser", systemImage: "safari")
                }
            } else if fieldType == .address {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .address)
                }) {
                    Label("Open in Maps", systemImage: "map")
                }
            }
        }
    }
}

struct VisibilityToggleRow: View {
    let field: FieldInfo
    let isVisible: Bool
    let onToggle: (Bool) -> Void

    private func icon(for type: String) -> String {
        switch type.lowercased() {
        case "email": "envelope"
        case "phone": "phone"
        case "website": "globe"
        case "address": "house"
        case "social": "at"
        default: "note.text"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: field.fieldType))
                .foregroundColor(isVisible ? .cyan : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(field.value)
                    .font(.body)
                    .foregroundColor(isVisible ? .primary : .secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .accessibilityLabel("Visibility for \(field.label)")
            .accessibilityValue(isVisible ? "Visible" : "Hidden")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

/// Section showing a contact's group memberships with manage button
struct ContactGroupsSection: View {
    let contactGroups: [VauchiVisibilityLabel]
    let onManageGroups: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Groups")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onManageGroups) {
                    Text("Manage")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
                .accessibilityLabel("Manage group memberships")
                .accessibilityHint("Opens a sheet to add or remove this contact from groups")
            }
            .padding(.horizontal)

            if contactGroups.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("Not in any group")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: onManageGroups) {
                        Text("Add to group")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .accessibilityLabel("Add to group")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            } else {
                ContactGroupBadges(
                    groups: contactGroups,
                    compact: false
                )
                .padding(.horizontal)
            }
        }
    }
}

/// Sheet for managing which groups a contact belongs to
struct ManageContactGroupsSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let contactId: String
    let contactName: String
    @Binding var isPresented: Bool
    let onUpdated: () -> Void

    @State private var allGroups: [VauchiVisibilityLabel] = []
    @State private var memberGroupIds: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading groups...")
                        .accessibilityLabel("Loading groups")
                } else if allGroups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text("No groups created yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Create groups in Settings > Contact Groups to organize your contacts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        Section {
                            ForEach(allGroups) { group in
                                let isMember = memberGroupIds.contains(group.id)
                                Button(action: {
                                    toggleGroupMembership(group: group, isMember: isMember)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isMember ? .cyan : .secondary)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.name)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("\(group.contactCount) member\(group.contactCount == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                                .disabled(isSaving)
                                .accessibilityLabel("\(group.name)\(isMember ? ", member" : "")")
                                .accessibilityHint("Double tap to \(isMember ? "remove from" : "add to") this group")
                            }
                        } header: {
                            Text("Groups for \(contactName)")
                        } footer: {
                            Text("Tap a group to add or remove this contact. Group membership controls which of your fields this contact can see.")
                        }
                    }
                }
            }
            .navigationTitle("Manage Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        isLoading = true
        await viewModel.loadLabels()
        allGroups = viewModel.visibilityLabels

        do {
            let currentGroups = try viewModel.getLabelsForContact(contactId: contactId)
            memberGroupIds = Set(currentGroups.map(\.id))
        } catch {
            memberGroupIds = []
        }
        isLoading = false
    }

    private func toggleGroupMembership(group: VauchiVisibilityLabel, isMember: Bool) {
        isSaving = true
        Task {
            do {
                if isMember {
                    try await viewModel.removeContactFromLabel(labelId: group.id, contactId: contactId)
                    memberGroupIds.remove(group.id)
                } else {
                    try await viewModel.addContactToLabel(labelId: group.id, contactId: contactId)
                    memberGroupIds.insert(group.id)
                }
                onUpdated()
            } catch {
                viewModel.showError("Error", message: "Failed to update group: \(error.localizedDescription)")
            }
            isSaving = false
        }
    }
}

struct ExchangeStatusBanner: View {
    let reciprocity: MobileReciprocity

    private var title: String {
        switch reciprocity {
        case .pending: "Awaiting confirmation"
        case .unreciprocated: "May not have your card"
        default: ""
        }
    }

    private var subtitle: String {
        switch reciprocity {
        case .pending: "Verifying that both sides completed the exchange"
        case .unreciprocated: "The other party may not have completed the exchange"
        default: ""
        }
    }

    private var icon: String {
        switch reciprocity {
        case .pending: "clock.arrow.circlepath"
        case .unreciprocated: "exclamationmark.triangle"
        default: "questionmark.circle"
        }
    }

    private var color: Color {
        switch reciprocity {
        case .pending: .orange
        case .unreciprocated: .red
        default: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exchange status: \(title)")
    }
}

/// Compact trust level badge for ContactDetail header.
struct TrustLevelBadge: View {
    let trustLevel: ContactTrustLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trustLevel.iconName)
                .foregroundColor(trustLevel.color)
                .accessibilityHidden(true)
            Text(trustLevel.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(trustLevel.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(trustLevel.color.opacity(0.15))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trust level: \(trustLevel.displayName)")
    }
}

/// Inline-editable private note below a contact's shared field.
struct ContactFieldNoteRow: View {
    let contactId: String
    let fieldId: String
    let note: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        if isEditing {
            HStack(spacing: 8) {
                TextField("Private note...", text: $editText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    onSave(editText)
                    isEditing = false
                }
                .font(.caption)
                .foregroundColor(.cyan)
                Button("Cancel") {
                    isEditing = false
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
        } else if !note.isEmpty {
            Button(action: {
                editText = note
                isEditing = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .accessibilityLabel("Field note: \(note)")
            .accessibilityHint("Tap to edit")
        } else {
            Button(action: {
                editText = ""
                isEditing = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("Add note")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
            .accessibilityLabel("Add private note to this field")
        }
    }
}
