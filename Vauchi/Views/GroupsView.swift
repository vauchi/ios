// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// GroupsView.swift
// Contact groups management view (built on visibility labels)
// Based on: features/visibility_labels.feature
// Part of: SP-20 Social Network

import SwiftUI
import VauchiMobile

/// Main view for managing contact groups (backed by visibility labels)
///
/// Groups are the user-facing term for "visibility labels" -- they organize
/// contacts into named collections and control what contact information
/// each group of people can see.
struct GroupsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showCreateSheet = false
    @State private var showDeleteConfirmation = false
    @State private var groupToDelete: VauchiVisibilityLabel?

    var body: some View {
        List {
            // Suggested groups section (if no groups exist yet)
            if viewModel.visibilityLabels.isEmpty, !viewModel.suggestedLabels.isEmpty {
                Section {
                    ForEach(viewModel.suggestedLabels, id: \.self) { suggestion in
                        Button(action: {
                            createGroup(name: suggestion)
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.cyan)
                                Text(suggestion)
                                Spacer()
                                Text("Tap to create")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accessibilityLabel("Create \(suggestion) group")
                        .accessibilityHint("Creates a new contact group named \(suggestion)")
                    }
                } header: {
                    Text("Suggested Groups")
                } footer: {
                    Text("Tap a suggestion to get started, or create your own custom group.")
                }
            }

            // Existing groups
            Section {
                if viewModel.visibilityLabels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text("No groups yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Create a group to organize your contacts and control what each group can see.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(viewModel.visibilityLabels) { group in
                        NavigationLink(destination: GroupDetailView(group: group)) {
                            GroupRow(group: group)
                        }
                        .accessibilityLabel("\(group.name), \(group.contactCount) contacts")
                        .accessibilityHint("Opens group details to manage members and visibility")
                    }
                    .onDelete(perform: deleteGroups)
                }
            } header: {
                if !viewModel.visibilityLabels.isEmpty {
                    Text("Your Groups (\(viewModel.visibilityLabels.count))")
                }
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new group")
                .accessibilityHint("Opens a sheet to create a new contact group")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateGroupSheet(isPresented: $showCreateSheet) { name in
                createGroup(name: name)
            }
        }
        .alert("Delete Group?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                groupToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let group = groupToDelete {
                    performDelete(group)
                }
            }
        } message: {
            if let group = groupToDelete {
                Text("Are you sure you want to delete \"\(group.name)\"? Contacts in this group will remain in your contacts list.")
            }
        }
        .task {
            await viewModel.loadLabels()
        }
    }

    private func createGroup(name: String) {
        Task {
            do {
                _ = try await viewModel.createLabel(name: name)
            } catch {
                viewModel.showError("Error", message: "Failed to create group: \(error.localizedDescription)")
            }
        }
    }

    private func deleteGroups(at offsets: IndexSet) {
        if let index = offsets.first {
            groupToDelete = viewModel.visibilityLabels[index]
            showDeleteConfirmation = true
        }
    }

    private func performDelete(_ group: VauchiVisibilityLabel) {
        Task {
            do {
                try await viewModel.deleteLabel(id: group.id)
            } catch {
                viewModel.showError("Error", message: "Failed to delete group: \(error.localizedDescription)")
            }
            groupToDelete = nil
        }
    }
}

/// Row view for a single group in the list
struct GroupRow: View {
    let group: VauchiVisibilityLabel

    var body: some View {
        HStack {
            // Group icon
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.3.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 14))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label("\(group.contactCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if group.visibleFieldCount > 0 {
                        Label("\(group.visibleFieldCount) fields visible", systemImage: "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Detail view for a single group -- manage members and field visibility
struct GroupDetailView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let group: VauchiVisibilityLabel

    @State private var groupDetail: VauchiVisibilityLabelDetail?
    @State private var showRenameSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showAddContactSheet = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .accessibilityLabel("Loading group details")
            } else if let detail = groupDetail {
                GroupDetailContent(
                    group: group,
                    detail: detail,
                    onRename: { showRenameSheet = true },
                    onDelete: { showDeleteConfirmation = true },
                    onAddContact: { showAddContactSheet = true },
                    onRemoveContact: removeContact,
                    onToggleFieldVisibility: toggleFieldVisibility,
                    onReload: { Task { await loadDetail() } }
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.3.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("Group Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text("This group may have been deleted.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showRenameSheet = true }) {
                        Label("Rename Group", systemImage: "pencil")
                    }
                    Button(action: { showAddContactSheet = true }) {
                        Label("Add Contacts", systemImage: "person.badge.plus")
                    }
                    Divider()
                    Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                        Label("Delete Group", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Group actions")
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameGroupSheet(
                currentName: group.name,
                isPresented: $showRenameSheet
            ) { newName in
                renameGroup(to: newName)
            }
        }
        .sheet(isPresented: $showAddContactSheet) {
            AddContactToGroupSheet(
                groupId: group.id,
                existingContactIds: groupDetail?.contactIds ?? [],
                isPresented: $showAddContactSheet,
                onAdded: { Task { await loadDetail() } }
            )
        }
        .alert("Delete Group?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteGroup()
            }
        } message: {
            Text("Are you sure you want to delete \"\(group.name)\"? Contacts will remain in your contacts list but will lose this group's visibility settings.")
        }
        .task {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        do {
            groupDetail = try viewModel.getLabel(id: group.id)
        } catch {
            groupDetail = nil
        }
        isLoading = false
    }

    private func renameGroup(to newName: String) {
        Task {
            do {
                try await viewModel.renameLabel(id: group.id, newName: newName)
                await loadDetail()
            } catch {
                viewModel.showError("Error", message: "Failed to rename group: \(error.localizedDescription)")
            }
        }
    }

    private func deleteGroup() {
        Task {
            do {
                try await viewModel.deleteLabel(id: group.id)
            } catch {
                viewModel.showError("Error", message: "Failed to delete group: \(error.localizedDescription)")
            }
        }
    }

    private func removeContact(contactId: String) {
        Task {
            do {
                try await viewModel.removeContactFromLabel(labelId: group.id, contactId: contactId)
                await loadDetail()
            } catch {
                viewModel.showError("Error", message: "Failed to remove contact: \(error.localizedDescription)")
            }
        }
    }

    private func toggleFieldVisibility(fieldLabel: String, isVisible: Bool) {
        Task {
            do {
                try await viewModel.setLabelFieldVisibility(labelId: group.id, fieldLabel: fieldLabel, isVisible: isVisible)
                await loadDetail()
            } catch {
                viewModel.showError("Error", message: "Failed to update field visibility: \(error.localizedDescription)")
            }
        }
    }
}

/// Content view for group details (separated for testability)
struct GroupDetailContent: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let group: VauchiVisibilityLabel
    let detail: VauchiVisibilityLabelDetail
    let onRename: () -> Void
    let onDelete: () -> Void
    let onAddContact: () -> Void
    let onRemoveContact: (String) -> Void
    let onToggleFieldVisibility: (String, Bool) -> Void
    let onReload: () -> Void

    var body: some View {
        List {
            // Group summary section
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(detail.name)
                        .foregroundColor(.secondary)
                    Text("Edit")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
                .contentShape(Rectangle())
                .onTapGesture { onRename() }
                .accessibilityLabel("Group name: \(detail.name)")
                .accessibilityHint("Double tap to rename this group")

                HStack {
                    Text("Members")
                    Spacer()
                    Text("\(detail.contactIds.count)")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("\(detail.contactIds.count) members")

                HStack {
                    Text("Visible Fields")
                    Spacer()
                    Text("\(detail.visibleFieldIds.count)")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("\(detail.visibleFieldIds.count) visible fields")
            } header: {
                Text("Group Info")
            }

            // Members section
            Section {
                if detail.contactIds.isEmpty {
                    Button(action: onAddContact) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(.cyan)
                            Text("Add contacts to this group")
                                .foregroundColor(.cyan)
                        }
                    }
                    .accessibilityLabel("Add contacts")
                    .accessibilityHint("Opens a sheet to add contacts to this group")
                } else {
                    ForEach(detail.contactIds, id: \.self) { contactId in
                        GroupMemberRow(
                            contactId: contactId,
                            contacts: viewModel.contacts,
                            onRemove: { onRemoveContact(contactId) }
                        )
                    }

                    Button(action: onAddContact) {
                        Label("Add More Contacts", systemImage: "person.badge.plus")
                            .foregroundColor(.cyan)
                    }
                    .accessibilityLabel("Add more contacts")
                    .accessibilityHint("Opens a sheet to add more contacts to this group")
                }
            } header: {
                Text("Members (\(detail.contactIds.count))")
            }

            // Field visibility section
            if let card = viewModel.card, !card.fields.isEmpty {
                Section {
                    ForEach(card.fields) { field in
                        let isVisible = detail.visibleFieldIds.contains(field.id)
                        Toggle(isOn: Binding(
                            get: { isVisible },
                            set: { onToggleFieldVisibility(field.id, $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.label)
                                    .font(.headline)
                                Text(field.value)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityLabel("Visibility for \(field.label)")
                        .accessibilityValue(isVisible ? "Visible to group" : "Hidden from group")
                    }
                } header: {
                    Text("Field Visibility")
                } footer: {
                    Text("Toggle which of your fields contacts in this group can see.")
                }
            }

            // Danger zone
            Section {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Group", systemImage: "trash")
                }
                .accessibilityLabel("Delete group")
                .accessibilityHint("Permanently delete this group. Contacts will remain in your list.")
            } footer: {
                Text("Deleting this group will not remove the contacts from your contacts list.")
            }
        }
    }
}

/// Row view for a group member
struct GroupMemberRow: View {
    let contactId: String
    let contacts: [ContactInfo]
    let onRemove: () -> Void

    @State private var showRemoveConfirmation = false

    private var contact: ContactInfo? {
        contacts.first { $0.id == contactId }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 36, height: 36)
                Text(String((contact?.displayName ?? "?").prefix(1)).uppercased())
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)

            if let contact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.body)
                    HStack(spacing: 4) {
                        if contact.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                                .accessibilityHidden(true)
                        }
                        Text(contact.verified ? "Verified" : "Not verified")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text(contactId)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Remove", systemImage: "person.badge.minus")
            }
        }
        .alert("Remove from Group?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onRemove()
            }
        } message: {
            Text("Remove \(contact?.displayName ?? "this contact") from the group? They will remain in your contacts list.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contact?.displayName ?? contactId)\(contact?.verified == true ? ", verified" : "")")
    }
}

/// Sheet to add contacts to a group
struct AddContactToGroupSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let groupId: String
    let existingContactIds: [String]
    @Binding var isPresented: Bool
    let onAdded: () -> Void

    @State private var searchText = ""
    @State private var selectedContactIds: Set<String> = []
    @State private var isAdding = false

    private var availableContacts: [ContactInfo] {
        let existingSet = Set(existingContactIds)
        let filtered = viewModel.contacts.filter { !existingSet.contains($0.id) }
        if searchText.isEmpty {
            return filtered
        }
        return filtered.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search contacts", text: $searchText)
                        .autocapitalization(.none)
                        .accessibilityLabel("Search contacts to add")
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding()

                if availableContacts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        if searchText.isEmpty {
                            Text("All contacts are already in this group")
                                .foregroundColor(.secondary)
                        } else {
                            Text("No matching contacts found")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(availableContacts) { contact in
                            Button(action: {
                                toggleSelection(contact.id)
                            }) {
                                HStack(spacing: 12) {
                                    // Selection indicator
                                    Image(systemName: selectedContactIds.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedContactIds.contains(contact.id) ? .cyan : .secondary)
                                        .font(.title3)

                                    // Avatar
                                    ZStack {
                                        Circle()
                                            .fill(Color.cyan)
                                            .frame(width: 36, height: 36)
                                        Text(String(contact.displayName.prefix(1)).uppercased())
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                    }
                                    .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        if contact.verified {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption2)
                                                Text("Verified")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                            }
                            .accessibilityLabel("\(contact.displayName)\(selectedContactIds.contains(contact.id) ? ", selected" : "")")
                            .accessibilityHint("Double tap to \(selectedContactIds.contains(contact.id) ? "deselect" : "select") this contact")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedContactIds.count))") {
                        addSelectedContacts()
                    }
                    .disabled(selectedContactIds.isEmpty || isAdding)
                }
            }
        }
    }

    private func toggleSelection(_ contactId: String) {
        if selectedContactIds.contains(contactId) {
            selectedContactIds.remove(contactId)
        } else {
            selectedContactIds.insert(contactId)
        }
    }

    private func addSelectedContacts() {
        isAdding = true
        Task {
            for contactId in selectedContactIds {
                do {
                    try await viewModel.addContactToLabel(labelId: groupId, contactId: contactId)
                } catch {
                    viewModel.showError("Error", message: "Failed to add contact: \(error.localizedDescription)")
                }
            }
            onAdded()
            isPresented = false
        }
    }
}

/// Sheet for creating a new group
struct CreateGroupSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void

    @State private var groupName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Group name", text: $groupName)
                        .focused($isNameFocused)
                        .autocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityLabel("Group name")
                        .accessibilityHint("Enter a name for your new group")
                        .onSubmit {
                            if isValid {
                                create()
                            }
                        }
                } footer: {
                    Text("Enter a name for your new group, like \"Family\" or \"Work Colleagues\".")
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private var isValid: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(name)
        isPresented = false
    }
}

/// Sheet for renaming a group
struct RenameGroupSheet: View {
    let currentName: String
    @Binding var isPresented: Bool
    let onRename: (String) -> Void

    @State private var newName: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Group name", text: $newName)
                        .focused($isNameFocused)
                        .autocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            if isValid {
                                rename()
                            }
                        }
                        .accessibilityLabel("Group name")
                        .accessibilityHint("Enter a new name for this group")
                } footer: {
                    Text("Enter a new name for this group.")
                }
            }
            .navigationTitle("Rename Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        rename()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            newName = currentName
            isNameFocused = true
        }
    }

    private var isValid: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentName
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        onRename(name)
        isPresented = false
    }
}

#Preview {
    NavigationView {
        GroupsView()
    }
    .environmentObject(VauchiViewModel())
}
