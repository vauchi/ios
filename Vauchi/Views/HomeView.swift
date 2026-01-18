// HomeView.swift
// Main card view

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showAddField = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with sync indicator
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hello, \(viewModel.card?.displayName ?? "User")!")
                                .font(.largeTitle)
                                .fontWeight(.bold)

                            if let publicId = viewModel.identity?.publicId {
                                Text("ID: \(String(publicId.prefix(16)))...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.monospaced)
                            }
                        }

                        Spacer()

                        // Sync indicator
                        SyncStatusIndicator(syncState: viewModel.syncState)
                    }
                    .padding(.horizontal)

                    // Card Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Your Card")
                                .font(.headline)
                            Spacer()
                            Button(action: { showAddField = true }) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.cyan)
                            }
                        }

                        if let fields = viewModel.card?.fields, !fields.isEmpty {
                            ForEach(fields) { field in
                                FieldRow(field: field, onDelete: {
                                    deleteField(field)
                                })
                            }
                        } else {
                            Text("No fields yet. Add your first field!")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Sync info
                    if viewModel.pendingUpdates > 0 {
                        HStack {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(.orange)
                            Text("\(viewModel.pendingUpdates) pending updates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if let lastSync = viewModel.lastSyncTime {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("Last synced: \(lastSync, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.sync() } }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.syncState == .syncing)
                }
            }
            .sheet(isPresented: $showAddField) {
                AddFieldSheet()
            }
            .refreshable {
                await viewModel.sync()
            }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }

    private func deleteField(_ field: FieldInfo) {
        Task {
            do {
                try await viewModel.removeField(id: field.id)
            } catch {
                viewModel.showError("Failed to Delete", message: error.localizedDescription)
            }
        }
    }
}

struct SyncStatusIndicator: View {
    let syncState: SyncState

    var body: some View {
        switch syncState {
        case .idle:
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
        case .syncing:
            ProgressView()
                .scaleEffect(0.8)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }
}

struct FieldRow: View {
    let field: FieldInfo
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    private func icon(for type: String) -> String {
        switch type.lowercased() {
        case "email": return "envelope"
        case "phone": return "phone"
        case "website": return "globe"
        case "address": return "house"
        case "social": return "at"
        default: return "note.text"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: field.fieldType))
                .foregroundColor(.cyan)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(field.value)
                    .font(.body)
            }

            Spacer()

            Button(action: { showDeleteAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .alert("Delete Field", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(field.label)\"?")
        }
    }
}

struct AddFieldSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss

    @State private var fieldType = "email"
    @State private var label = ""
    @State private var value = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    let fieldTypes = ["email", "phone", "website", "address", "social", "custom"]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Type", selection: $fieldType) {
                        ForEach(fieldTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }

                    TextField("Label", text: $label)
                        .autocapitalization(.words)

                    TextField("Value", text: $value)
                        .autocapitalization(.none)
                        .keyboardType(keyboardType(for: fieldType))
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addField() }
                        .disabled(label.isEmpty || value.isEmpty || isLoading)
                }
            }
        }
    }

    private func keyboardType(for type: String) -> UIKeyboardType {
        switch type {
        case "email": return .emailAddress
        case "phone": return .phonePad
        case "website": return .URL
        default: return .default
        }
    }

    private func addField() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.addField(type: fieldType, label: label, value: value)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(VauchiViewModel())
}
