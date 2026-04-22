// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ArchivedContactsView.swift
// Shows archived contacts with unarchive action

import SwiftUI

struct ArchivedContactsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        Group {
            if viewModel.archivedContacts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)

                    Text(localizationService.t("contacts.no_archived"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("archived_contacts.empty")
            } else {
                List {
                    ForEach(viewModel.archivedContacts) { contact in
                        HStack(spacing: 12) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 44, height: 44)

                                Text(String(contact.displayName.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName)
                                    .font(Font.body.weight(.medium))

                                if contact.addedAt > 0 {
                                    let addedAt = Date(timeIntervalSince1970: TimeInterval(contact.addedAt))
                                    Text("Added \(addedAt, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                Task {
                                    do {
                                        let name = contact.displayName
                                        try await viewModel.unarchiveContact(id: contact.id)
                                        await viewModel.loadArchivedContacts()
                                        viewModel.showToast(localizationService.t("contacts.toast_unarchived"))
                                    } catch {
                                        viewModel.showError(
                                            "Unarchive Failed",
                                            message: error.localizedDescription
                                        )
                                    }
                                }
                            } label: {
                                Label(
                                    localizationService.t("contacts.action_unarchive"),
                                    systemImage: "arrow.uturn.backward"
                                )
                                .font(.caption)
                                .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Unarchive \(contact.displayName)")
                            .accessibilityHint("Move this contact back to your main contact list")
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("archived_contacts.row")
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(contact.displayName), \(contact.isVerified ? "verified" : "not verified")")
                        .accessibilityHint("Double tap to unarchive this contact")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(localizationService.t("contacts.archived_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.loadArchivedContacts()
            }
        }
    }
}

#Preview {
    NavigationView {
        ArchivedContactsView()
            .environmentObject(VauchiViewModel())
    }
}
