// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactMergeView.swift
// Duplicate contact detection and merge UI.

import SwiftUI

struct ContactMergeView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        Group {
            if viewModel.duplicatePairs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.badge.gearshape")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)

                    Text(localizationService.t("contacts.no_duplicates"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("contact_merge.empty")
            } else {
                List {
                    ForEach(Array(viewModel.duplicatePairs.enumerated()), id: \.offset) { _, entry in
                        DuplicatePairRow(
                            pair: entry.pair,
                            contact1: entry.contact1,
                            contact2: entry.contact2,
                            localizationService: localizationService,
                            viewModel: viewModel
                        )
                        .accessibilityIdentifier("contact_merge.row")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(localizationService.t("contacts.find_duplicates"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.loadDuplicates()
            }
        }
    }
}

private struct DuplicatePairRow: View {
    let pair: MobileDuplicatePair
    let contact1: ContactInfo
    let contact2: ContactInfo
    @ObservedObject var localizationService: LocalizationService
    @ObservedObject var viewModel: VauchiViewModel

    @State private var swapped = false

    private var exchangedLocked: Bool {
        (!contact1.isImported && contact2.isImported) || (contact1.isImported && !contact2.isImported)
    }

    private var primary: ContactInfo {
        if exchangedLocked {
            return !contact1.isImported ? contact1 : contact2
        }
        return swapped ? contact2 : contact1
    }

    private var secondary: ContactInfo {
        if exchangedLocked {
            return !contact1.isImported ? contact2 : contact1
        }
        return swapped ? contact1 : contact2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(localizationService.t("contacts.merge_similarity")
                    .replacingOccurrences(of: "{percent}", with: "\(Int(pair.similarity * 100))"))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
                    .accessibilityIdentifier("contact_merge.similarity_badge")
            }

            contactRow(contact: primary, isPrimary: true)
            contactRow(contact: secondary, isPrimary: false)

            if exchangedLocked {
                Text(localizationService.t("contacts.merge_exchanged_primary"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("contact_merge.exchanged_hint")
            } else if !swapped {
                Button {
                    swapped.toggle()
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.cyan)
                .accessibilityLabel("Swap primary and secondary contact")
                .accessibilityIdentifier("contact_merge.swap_button")
            } else {
                Button {
                    swapped.toggle()
                } label: {
                    Label("Swap back", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.cyan)
                .accessibilityLabel("Swap primary and secondary contact back")
                .accessibilityIdentifier("contact_merge.swap_button")
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            try await viewModel.mergeContacts(
                                primaryId: primary.id, secondaryId: secondary.id
                            )
                            viewModel.showToast(localizationService.t("contacts.toast_merged"))
                            await viewModel.loadDuplicates()
                        } catch {
                            viewModel.showError("Merge Failed", message: error.localizedDescription)
                        }
                    }
                } label: {
                    Label(localizationService.t("contacts.merge_confirm"), systemImage: "arrow.triangle.merge")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("contact_merge.merge_button")

                Button {
                    Task {
                        do {
                            try await viewModel.dismissDuplicate(id1: pair.id1, id2: pair.id2)
                            await viewModel.loadDuplicates()
                        } catch {
                            viewModel.showError("Dismiss Failed", message: error.localizedDescription)
                        }
                    }
                } label: {
                    Text(localizationService.t("contacts.merge_dismiss"))
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("contact_merge.dismiss_button")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func contactRow(contact: ContactInfo, isPrimary: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 36, height: 36)
                Text(String(contact.displayName.prefix(1)).uppercased())
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)

            Text(contact.displayName)
                .font(.body)

            if isPrimary {
                Text(localizationService.t("contacts.merge_suggested_primary"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(6)
                    .accessibilityIdentifier("contact_merge.suggested_badge")
            }
        }
        .accessibilityLabel("\(contact.displayName)\(isPrimary ? ", suggested primary" : "")")
    }
}

#Preview {
    NavigationView {
        ContactMergeView()
            .environmentObject(VauchiViewModel())
    }
}
