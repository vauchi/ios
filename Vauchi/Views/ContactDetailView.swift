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
    @State private var fieldVisibility: [String: Bool] = [:]
    @State private var isLoadingVisibility = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 80, height: 80)

                        Text(String(contact.displayName.prefix(1)).uppercased())
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    }

                    Text(contact.displayName)
                        .font(.title)
                        .fontWeight(.bold)

                    HStack(spacing: 4) {
                        if contact.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                        }
                        Text(contact.verified ? "Verified" : "Not verified")
                            .foregroundColor(.secondary)
                    }

                    Text("ID: \(String(contact.id.prefix(16)))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)

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
                    }
                }
                .padding()

                // Contact's card info section
                if let card = contact.card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Contact Info")
                            .font(.headline)
                            .padding(.horizontal)

                        if card.fields.isEmpty {
                            Text("No visible fields")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(card.fields) { field in
                                    ContactFieldRow(field: field)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Visibility section - what this contact can see of YOUR card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Visibility")
                        .font(.headline)
                        .padding(.horizontal)

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
                    Label("Remove Contact", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVisibility()
        }
        .alert("Remove Contact", isPresented: $showRemoveAlert) {
            Button("Cancel", role: .cancel) { }
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
            Button("Cancel", role: .cancel) { }
            Button("Verify") {
                verifyContact()
            }
        } message: {
            Text("By verifying \(contact.displayName), you confirm that you have verified their identity in person (e.g., by comparing fingerprints).")
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
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

    private var fieldType: VauchiFieldType {
        VauchiFieldType(rawValue: field.fieldType) ?? .custom
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

            // Quick action buttons using ContactActions
            if fieldType == .email {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .email)
                }) {
                    Image(systemName: "envelope.circle")
                        .foregroundColor(.blue)
                }
            } else if fieldType == .phone {
                HStack(spacing: 8) {
                    Button(action: {
                        ContactActions.openField(value: field.value, type: .phone)
                    }) {
                        Image(systemName: "phone.circle")
                            .foregroundColor(.green)
                    }
                    Button(action: {
                        if let url = ContactActions.buildSmsUrl(for: field.value) {
                            ContactActions.openUrl(url)
                        }
                    }) {
                        Image(systemName: "message.circle")
                            .foregroundColor(.blue)
                    }
                }
            } else if fieldType == .website {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .website)
                }) {
                    Image(systemName: "safari")
                        .foregroundColor(.blue)
                }
            } else if fieldType == .address {
                Button(action: {
                    ContactActions.openField(value: field.value, type: .address)
                }) {
                    Image(systemName: "map")
                        .foregroundColor(.orange)
                }
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
                .foregroundColor(isVisible ? .cyan : .secondary)
                .frame(width: 24)

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
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationView {
        ContactDetailView(contact: ContactInfo(id: "test", displayName: "Alice", verified: true))
            .environmentObject(VauchiViewModel())
    }
}
