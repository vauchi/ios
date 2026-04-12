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
            } else {
                List {
                    ForEach(viewModel.archivedContacts) { contact in
                        HStack {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 44, height: 44)

                                Text(String(contact.displayName.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName)
                                    .font(.body)
                                    .fontWeight(.medium)

                                if let addedAt = contact.addedAt {
                                    Text("Added \(addedAt, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                Task {
                                    do {
                                        try await viewModel.unarchiveContact(id: contact.id)
                                        await viewModel.loadArchivedContacts()
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
                        .accessibilityElement(children: .combine)
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
