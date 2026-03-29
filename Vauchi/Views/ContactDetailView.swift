// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactDetailView.swift
// Contact detail view with visibility controls

import SwiftUI

struct ContactDetailView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    let contact: ContactInfo

    @State private var showRemoveAlert = false
    @State private var showVerifyAlert = false
    @State private var isVerifying = false
    @State private var isTogglingTrust = false
    @State private var isTogglingHidden = false
    @State private var fieldVisibility: [String: Bool] = [:]
    @State private var isLoadingVisibility = true
    @State private var contactGroups: [VauchiVisibilityLabel] = []
    @State private var showManageGroupsSheet = false
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 80, height: 80)
                            .accessibilityHidden(true)

                        Text(String(contact.displayName.prefix(1)).uppercased())
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Profile picture for \(contact.displayName)")

                    Text(contact.displayName)
                        .font(.title)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 4) {
                        if contact.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .accessibilityHidden(true)
                        }
                        Text(contact.verified ? localizationService.t("contacts.verified") : localizationService.t("contacts.not_verified"))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    Text(contact.fingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("Contact fingerprint: \(contact.fingerprint)")

                    if let addedAt = contact.addedAt {
                        Text("Added \(addedAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Verify button
                    if !contact.verified {
                        Button(action: { showVerifyAlert = true }) {
                            Label("Verify Contact", systemImage: "checkmark.seal")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                        }
                        .disabled(isVerifying)
                        .accessibilityLabel("Verify contact")
                        .accessibilityHint("Mark this contact as verified after confirming their identity in person")
                    }

                    // Recovery trust indicator
                    if contact.recoveryTrusted {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.cyan)
                                .accessibilityHidden(true)
                            Text("Recovery Trusted")
                                .foregroundColor(.cyan)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Recovery trusted contact")
                    }

                    // Recovery trust toggle
                    Button(action: {
                        isTogglingTrust = true
                        Task {
                            do {
                                if contact.recoveryTrusted {
                                    try await viewModel.untrustContactForRecovery(id: contact.id)
                                } else {
                                    try await viewModel.trustContactForRecovery(id: contact.id)
                                }
                            } catch {
                                viewModel.showError("Error", message: error.localizedDescription)
                            }
                            isTogglingTrust = false
                        }
                    }) {
                        Label(
                            contact.recoveryTrusted ? "Remove Recovery Trust" : "Trust for Recovery",
                            systemImage: contact.recoveryTrusted ? "shield.slash" : "shield.checkered"
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(contact.recoveryTrusted ? Color.gray.opacity(0.2) : Color.cyan.opacity(0.2))
                        .foregroundColor(contact.recoveryTrusted ? .gray : .cyan)
                        .cornerRadius(8)
                    }
                    .disabled(isTogglingTrust)
                    .accessibilityLabel(contact.recoveryTrusted ? "Remove recovery trust" : "Trust for recovery")
                    .accessibilityHint(contact.recoveryTrusted ? "Remove this contact from your recovery helpers" : "Allow this contact to help you recover your account")

                    // Hide/unhide toggle
                    Button(action: {
                        isTogglingHidden = true
                        Task {
                            do {
                                if contact.isHidden {
                                    try await viewModel.unhideContact(id: contact.id)
                                } else {
                                    try await viewModel.hideContact(id: contact.id)
                                    dismiss()
                                }
                            } catch {
                                viewModel.showError("Error", message: error.localizedDescription)
                            }
                            isTogglingHidden = false
                        }
                    }) {
                        Label(
                            contact.isHidden ? "Unhide Contact" : "Hide Contact",
                            systemImage: contact.isHidden ? "eye.fill" : "eye.slash"
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(contact.isHidden ? Color.gray.opacity(0.2) : Color.orange.opacity(0.2))
                        .foregroundColor(contact.isHidden ? .gray : .orange)
                        .cornerRadius(8)
                    }
                    .disabled(isTogglingHidden)
                    .accessibilityLabel(contact.isHidden ? "Unhide contact" : "Hide contact")
                    .accessibilityHint(contact.isHidden ? "Make this contact visible in your contact list" : "Hide this contact from your contact list")
                }
                .padding()

                // Contact's card info section
                if let card = contact.card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(localizationService.t("contacts.info"))
                            .font(.headline)
                            .padding(.horizontal)
                            .accessibilityAddTraits(.isHeader)

                        if card.fields.isEmpty {
                            Text(localizationService.t("contacts.no_info"))
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(card.fields) { field in
                                    ContactFieldRow(field: field, contactId: contact.id)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Groups section
                ContactGroupsSection(
                    contactGroups: contactGroups,
                    onManageGroups: { showManageGroupsSheet = true }
                )

                // Visibility section - what this contact can see of YOUR card
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizationService.t("visibility.title"))
                        .font(.headline)
                        .padding(.horizontal)
                        .accessibilityAddTraits(.isHeader)

                    Text("Control which of your fields this contact can see.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    if let myCard = viewModel.card {
                        if myCard.fields.isEmpty {
                            Text("You have no fields to share")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(myCard.fields) { field in
                                    VisibilityToggleRow(
                                        field: field,
                                        isVisible: fieldVisibility[field.label] ?? true,
                                        onToggle: { newValue in
                                            toggleVisibility(field: field, visible: newValue)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        if isLoadingVisibility {
                            ProgressView()
                                .padding()
                        } else {
                            Text("Unable to load your card")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }

                Spacer(minLength: 40)

                // Remove button
                Button(role: .destructive) {
                    showRemoveAlert = true
                } label: {
                    Label(localizationService.t("action.delete"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .accessibilityLabel("Remove contact")
                .accessibilityHint("Permanently delete this contact from your list")
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVisibility()
            loadContactGroups()
        }
        .sheet(isPresented: $showManageGroupsSheet) {
            ManageContactGroupsSheet(
                contactId: contact.id,
                contactName: contact.displayName,
                isPresented: $showManageGroupsSheet,
                onUpdated: { loadContactGroups() }
            )
        }
        .alert("Remove Contact", isPresented: $showRemoveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        try await viewModel.removeContact(id: contact.id)
                        dismiss()
                    } catch {
                        viewModel.showError("Failed to Remove", message: error.localizedDescription)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to remove \(contact.displayName)?")
        }
        .alert("Verify Contact", isPresented: $showVerifyAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Verify") {
                verifyContact()
            }
        } message: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare these fingerprints with \(contact.displayName) in person:")
                Text("Theirs: \(contact.fingerprint)")
                    .font(.system(.caption, design: .monospaced))
                if let ownFp = viewModel.getOwnFingerprint() {
                    Text("Yours: \(ownFp)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }

    private func loadContactGroups() {
        do {
            contactGroups = try viewModel.getLabelsForContact(contactId: contact.id)
        } catch {
            contactGroups = []
        }
    }

    private func loadVisibility() {
        isLoadingVisibility = true

        Task {
            guard let myCard = viewModel.card else {
                isLoadingVisibility = false
                return
            }

            var visibility: [String: Bool] = [:]
            for field in myCard.fields {
                do {
                    let isVisible = try await viewModel.isFieldVisibleToContact(
                        contactId: contact.id,
                        fieldLabel: field.label
                    )
                    visibility[field.label] = isVisible
                } catch {
                    visibility[field.label] = true // Default to visible
                }
            }

            fieldVisibility = visibility
            isLoadingVisibility = false
        }
    }

    private func toggleVisibility(field: FieldInfo, visible: Bool) {
        fieldVisibility[field.label] = visible

        Task {
            do {
                if visible {
                    try await viewModel.showFieldToContact(contactId: contact.id, fieldLabel: field.label)
                } else {
                    try await viewModel.hideFieldFromContact(contactId: contact.id, fieldLabel: field.label)
                }
            } catch {
                // Revert on error
                fieldVisibility[field.label] = !visible
                viewModel.showError("Visibility Update Failed", message: error.localizedDescription)
            }
        }
    }

    private func verifyContact() {
        isVerifying = true

        Task {
            do {
                try await viewModel.verifyContact(id: contact.id)
                viewModel.showSuccess("Contact Verified", message: "\(contact.displayName) has been marked as verified.")
            } catch {
                viewModel.showError("Verification Failed", message: error.localizedDescription)
            }
            isVerifying = false
        }
    }
}

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

#Preview {
    NavigationView {
        ContactDetailView(contact: ContactInfo(id: "test", displayName: "Alice", verified: true))
            .environmentObject(VauchiViewModel())
    }
}
