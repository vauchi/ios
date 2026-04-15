// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactDetailView.swift
// Contact detail view with visibility controls

import SwiftUI
import VauchiPlatform

struct ContactDetailView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.dismiss) var dismiss
    let contact: ContactInfo

    @State private var showVerifyAlert = false
    @State private var isVerifying = false
    @State private var isTogglingTrust = false
    @State private var isTogglingHidden = false
    @State private var isTogglingProposalTrust = false
    @State private var fieldVisibility: [String: Bool] = [:]
    @State private var isLoadingVisibility = true
    @State private var contactGroups: [VauchiVisibilityLabel] = []
    @State private var showManageGroupsSheet = false
    @State private var personalNote: String = ""
    @State private var isEditingNote = false
    @State private var fieldNotes: [String: String] = [:]
    @State private var proposalTrusted: Bool = false
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

                    // Trust level badge
                    TrustLevelBadge(trustLevel: ContactTrustLevel(from: contact.trustLevel))

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

                    // Exchange status (reciprocity)
                    if contact.reciprocity == .pending || contact.reciprocity == .unreciprocated {
                        ExchangeStatusBanner(reciprocity: contact.reciprocity)
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

                    // Proposal trust toggle
                    Button(action: {
                        isTogglingProposalTrust = true
                        Task {
                            do {
                                let newValue = !proposalTrusted
                                try await viewModel.setProposalTrusted(contactId: contact.id, trusted: newValue)
                                proposalTrusted = newValue
                            } catch {
                                viewModel.showError("Error", message: error.localizedDescription)
                            }
                            isTogglingProposalTrust = false
                        }
                    }) {
                        Label(
                            proposalTrusted ? "Remove Proposal Trust" : "Trust for Proposals",
                            systemImage: proposalTrusted ? "person.badge.minus" : "person.badge.plus"
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(proposalTrusted ? Color.gray.opacity(0.2) : Color.purple.opacity(0.2))
                        .foregroundColor(proposalTrusted ? .gray : .purple)
                        .cornerRadius(8)
                    }
                    .disabled(isTogglingProposalTrust)
                    .accessibilityLabel(proposalTrusted ? "Remove proposal trust" : "Trust for proposals")
                    .accessibilityHint(
                        proposalTrusted
                            ? "Stop allowing this contact to propose new contacts to you"
                            : "Allow this contact to propose new contacts to you"
                    )
                }
                .padding()

                // Personal note section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Note")
                        .font(.headline)
                        .padding(.horizontal)
                        .accessibilityAddTraits(.isHeader)

                    if isEditingNote {
                        VStack(spacing: 8) {
                            TextEditor(text: $personalNote)
                                .frame(minHeight: 60, maxHeight: 120)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .accessibilityLabel("Private note")

                            HStack {
                                Button("Cancel") {
                                    isEditingNote = false
                                    // Reload original note
                                    Task {
                                        personalNote = await (try? viewModel.getContactNote(contactId: contact.id)) ?? ""
                                    }
                                }
                                .foregroundColor(.secondary)

                                Spacer()

                                Button("Save") {
                                    Task {
                                        do {
                                            try await viewModel.setContactNote(contactId: contact.id, note: personalNote)
                                        } catch {
                                            viewModel.showError("Error", message: error.localizedDescription)
                                        }
                                        isEditingNote = false
                                    }
                                }
                                .foregroundColor(.cyan)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Button(action: { isEditingNote = true }) {
                            HStack {
                                Text(personalNote.isEmpty ? "Add a private note..." : personalNote)
                                    .foregroundColor(personalNote.isEmpty ? .secondary : .primary)
                                    .lineLimit(3)
                                Spacer()
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .accessibilityLabel(personalNote.isEmpty ? "Add a private note" : "Private note: \(personalNote)")
                        .accessibilityHint("Tap to edit your private note about this contact")
                    }

                    Text("Only visible to you — never shared with this contact.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

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
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(card.fields) { field in
                                    VStack(spacing: 4) {
                                        ContactFieldRow(field: field, contactId: contact.id)
                                        ContactFieldNoteRow(
                                            contactId: contact.id,
                                            fieldId: field.id,
                                            note: fieldNotes[field.id] ?? "",
                                            onSave: { newNote in
                                                Task {
                                                    do {
                                                        if newNote.isEmpty {
                                                            try await viewModel.deleteContactFieldNote(contactId: contact.id, fieldId: field.id)
                                                        } else {
                                                            try await viewModel.setContactFieldNote(contactId: contact.id, fieldId: field.id, note: newNote)
                                                        }
                                                        fieldNotes[field.id] = newNote.isEmpty ? nil : newNote
                                                    } catch {
                                                        viewModel.showError("Error", message: error.localizedDescription)
                                                    }
                                                }
                                            }
                                        )
                                    }
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
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
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

                // Archive / Delete button
                if contact.isImported {
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await viewModel.softDeleteImportedContact(id: contact.id)
                                let contactId = contact.id
                                viewModel.showToast(
                                    localizationService.t("contacts.toast_deleted"),
                                    undoHandler: {
                                        try await viewModel.undoDeleteImportedContact(id: contactId)
                                    }
                                )
                                dismiss()
                            } catch {
                                viewModel.showError("Delete Failed", message: error.localizedDescription)
                            }
                        }
                    } label: {
                        Label(localizationService.t("action.delete"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Delete contact")
                    .accessibilityHint("Delete this imported contact with undo option")
                } else {
                    Button {
                        Task {
                            do {
                                try await viewModel.archiveContact(id: contact.id)
                                await viewModel.loadContacts()
                                let contactId = contact.id
                                viewModel.showToast(
                                    localizationService.t("contacts.toast_archived"),
                                    undoHandler: {
                                        try await viewModel.unarchiveContact(id: contactId)
                                        await viewModel.loadContacts()
                                    }
                                )
                                dismiss()
                            } catch {
                                viewModel.showError("Archive Failed", message: error.localizedDescription)
                            }
                        }
                    } label: {
                        Label(localizationService.t("contacts.action_archive"), systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal)
                    .accessibilityLabel("Archive contact")
                    .accessibilityHint("Move this contact to the archive with undo option")
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVisibility()
            loadContactGroups()
            loadNotes()
            proposalTrusted = contact.proposalTrusted
        }
        .sheet(isPresented: $showManageGroupsSheet) {
            ManageContactGroupsSheet(
                contactId: contact.id,
                contactName: contact.displayName,
                isPresented: $showManageGroupsSheet,
                onUpdated: { loadContactGroups() }
            )
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

    private func loadNotes() {
        Task {
            personalNote = await (try? viewModel.getContactNote(contactId: contact.id)) ?? ""
            if let notes = try? await viewModel.getContactFieldNotes(contactId: contact.id) {
                var map: [String: String] = [:]
                for note in notes {
                    map[note.fieldId] = note.note
                }
                fieldNotes = map
            }
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

#Preview {
    NavigationView {
        ContactDetailView(contact: ContactInfo(id: "test", displayName: "Alice", verified: true))
            .environmentObject(VauchiViewModel())
    }
}
