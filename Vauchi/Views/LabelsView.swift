// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// LabelsView.swift
// Visibility labels management view
// Based on: features/visibility_labels.feature

import SwiftUI

/// Main view for managing visibility labels
struct LabelsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showCreateSheet = false
    @State private var newLabelName = ""
    @State private var showDeleteConfirmation = false
    @State private var labelToDelete: VauchiVisibilityLabel?

    var body: some View {
        List {
            // Suggested labels section (if no labels exist)
            if viewModel.visibilityLabels.isEmpty, !viewModel.suggestedLabels.isEmpty {
                Section {
                    ForEach(viewModel.suggestedLabels, id: \.self) { suggestion in
                        Button(action: {
                            createLabel(name: suggestion)
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.cyan)
                                Text(suggestion)
                                Spacer()
                                Text("Tap to create")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accessibilityLabel("Create \(suggestion) label")
                        .accessibilityHint("Creates a new visibility label named \(suggestion)")
                    }
                } header: {
                    Text("Suggested Labels")
                } footer: {
                    Text("Tap a suggestion to create it, or create your own custom label.")
                }
            }

            // Existing labels
            Section {
                if viewModel.visibilityLabels.isEmpty {
                    Text("No labels yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(viewModel.visibilityLabels) { label in
                        NavigationLink(destination: LabelDetailView(label: label)) {
                            LabelRow(label: label)
                        }
                        .accessibilityLabel("\(label.name), \(label.contactCount) contacts")
                        .accessibilityHint("Opens label details")
                    }
                    .onDelete(perform: deleteLabels)
                }
            } header: {
                Text("Your Labels")
            } footer: {
                Text("Labels help you organize contacts into groups and control what information each group can see.")
            }
        }
        .navigationTitle("Visibility Labels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new label")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateLabelSheet(isPresented: $showCreateSheet) { name in
                createLabel(name: name)
            }
        }
        .alert("Delete Label?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                labelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let label = labelToDelete {
                    deleteLabel(label)
                }
            }
        } message: {
            if let label = labelToDelete {
                Text("Are you sure you want to delete \"\(label.name)\"? Contacts in this label will remain in your contacts list.")
            }
        }
        .task {
            await viewModel.loadLabels()
        }
    }

    private func createLabel(name: String) {
        Task {
            do {
                _ = try await viewModel.createLabel(name: name)
            } catch {
                viewModel.showError("Error", message: "Failed to create label: \(error.localizedDescription)")
            }
        }
    }

    private func deleteLabels(at offsets: IndexSet) {
        if let index = offsets.first {
            labelToDelete = viewModel.visibilityLabels[index]
            showDeleteConfirmation = true
        }
    }

    private func deleteLabel(_ label: VauchiVisibilityLabel) {
        Task {
            do {
                try await viewModel.deleteLabel(id: label.id)
            } catch {
                viewModel.showError("Error", message: "Failed to delete label: \(error.localizedDescription)")
            }
            labelToDelete = nil
        }
    }
}

/// Row view for a single label
struct LabelRow: View {
    let label: VauchiVisibilityLabel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.name)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label("\(label.contactCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if label.visibleFieldCount > 0 {
                        Label("\(label.visibleFieldCount) fields", systemImage: "eye")
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

/// Sheet for creating a new label
struct CreateLabelSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void

    @State private var labelName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Label name", text: $labelName)
                        .focused($isNameFocused)
                        .autocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityLabel("Label name")
                        .accessibilityHint("Enter a name for your new visibility label")
                        .onSubmit {
                            if isValid {
                                create()
                            }
                        }
                } footer: {
                    Text("Enter a name for your new label, like \"Family\" or \"Work Colleagues\".")
                }
            }
            .navigationTitle("New Label")
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
        !labelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        let name = labelName.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(name)
        isPresented = false
    }
}

#Preview {
    NavigationView {
        LabelsView()
    }
    .environmentObject(VauchiViewModel())
}
