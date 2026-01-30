// LabelDetailView.swift
// Detail view for editing a visibility label
// Based on: features/visibility_labels.feature

import SwiftUI
import VauchiMobile

/// Detail view for a visibility label
struct LabelDetailView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let label: VauchiVisibilityLabel

    @State private var labelDetail: VauchiVisibilityLabelDetail?
    @State private var showRenameSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let detail = labelDetail {
                LabelDetailContent(
                    label: label,
                    detail: detail,
                    onRename: { showRenameSheet = true },
                    onDelete: { showDeleteConfirmation = true },
                    onToggleFieldVisibility: toggleFieldVisibility
                )
            } else {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "Label Not Found",
                        systemImage: "tag.slash",
                        description: Text("This label may have been deleted.")
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Label Not Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("This label may have been deleted.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(label.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRenameSheet) {
            RenameLabelSheet(
                currentName: label.name,
                isPresented: $showRenameSheet
            ) { newName in
                renameLabel(to: newName)
            }
        }
        .alert("Delete Label?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteLabel()
            }
        } message: {
            Text("Are you sure you want to delete \"\(label.name)\"? Contacts will remain in your contacts list but will lose this label's visibility settings.")
        }
        .task {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        do {
            labelDetail = try viewModel.getLabel(id: label.id)
        } catch {
            labelDetail = nil
        }
        isLoading = false
    }

    private func renameLabel(to newName: String) {
        Task {
            do {
                try await viewModel.renameLabel(id: label.id, newName: newName)
                await loadDetail()
            } catch {
                viewModel.showError("Error", message: "Failed to rename label: \(error.localizedDescription)")
            }
        }
    }

    private func deleteLabel() {
        Task {
            do {
                try await viewModel.deleteLabel(id: label.id)
            } catch {
                viewModel.showError("Error", message: "Failed to delete label: \(error.localizedDescription)")
            }
        }
    }

    private func toggleFieldVisibility(fieldLabel: String, isVisible: Bool) {
        Task {
            do {
                try await viewModel.setLabelFieldVisibility(labelId: label.id, fieldLabel: fieldLabel, isVisible: isVisible)
                await loadDetail()
            } catch {
                viewModel.showError("Error", message: "Failed to update field visibility: \(error.localizedDescription)")
            }
        }
    }
}

/// Content view for label details
struct LabelDetailContent: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let label: VauchiVisibilityLabel
    let detail: VauchiVisibilityLabelDetail
    let onRename: () -> Void
    let onDelete: () -> Void
    let onToggleFieldVisibility: (String, Bool) -> Void

    var body: some View {
        List {
            // Label info section
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
                .onTapGesture {
                    onRename()
                }

                HStack {
                    Text("Contacts")
                    Spacer()
                    Text("\(detail.contactIds.count)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Visible Fields")
                    Spacer()
                    Text("\(detail.visibleFieldIds.count)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Label Info")
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
                    }
                } header: {
                    Text("Field Visibility")
                } footer: {
                    Text("Toggle which of your fields contacts in this label can see.")
                }
            }

            // Contacts section
            Section {
                if detail.contactIds.isEmpty {
                    Text("No contacts in this label")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(detail.contactIds, id: \.self) { contactId in
                        if let contact = viewModel.contacts.first(where: { $0.id == contactId }) {
                            HStack {
                                Text(contact.displayName)
                                Spacer()
                                if contact.verified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                        } else {
                            Text(contactId)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Contacts (\(detail.contactIds.count))")
            } footer: {
                Text("To add or remove contacts, go to the contact's detail page and manage their labels.")
            }

            // Danger zone
            Section {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Label", systemImage: "trash")
                }
            } footer: {
                Text("Deleting this label will not remove the contacts from your contacts list.")
            }
        }
    }
}

/// Sheet for renaming a label
struct RenameLabelSheet: View {
    let currentName: String
    @Binding var isPresented: Bool
    let onRename: (String) -> Void

    @State private var newName: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Label name", text: $newName)
                        .focused($isNameFocused)
                        .autocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            if isValid {
                                rename()
                            }
                        }
                } footer: {
                    Text("Enter a new name for this label.")
                }
            }
            .navigationTitle("Rename Label")
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
        LabelDetailView(label: VauchiVisibilityLabel(
            from: MobileVisibilityLabel(
                id: "test-id",
                name: "Family",
                contactCount: 3,
                visibleFieldCount: 2,
                createdAt: 0,
                modifiedAt: 0
            )
        ))
    }
    .environmentObject(VauchiViewModel())
}
