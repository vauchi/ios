// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactsView.swift
// Contact list view with search

import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [ContactInfo] = []
    @State private var showHiddenContacts = false
    @ObservedObject private var localizationService = LocalizationService.shared

    private var displayedContacts: [ContactInfo] {
        if searchText.isEmpty {
            viewModel.contacts
        } else {
            searchResults
        }
    }

    private var contactCount: Int {
        viewModel.contacts.count
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.contacts.isEmpty, searchText.isEmpty {
                    EmptyContactsView()
                } else {
                    VStack(spacing: 0) {
                        // Contact count header
                        if !searchText.isEmpty || !viewModel.contacts.isEmpty {
                            HStack {
                                Text("\(contactCount) contact\(contactCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(showHiddenContacts ? .purple : .secondary)
                                Spacer()
                                if showHiddenContacts {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(showHiddenContacts ? Color.purple.opacity(0.1) : Color(.systemGroupedBackground))
                            .onTapGesture(count: 3) {
                                toggleHiddenContactsMode()
                            }
                            .accessibilityLabel("Contact count header")
                            .accessibilityHint("Triple tap to toggle hidden contacts view")
                        }

                        if displayedContacts.isEmpty, !searchText.isEmpty {
                            // No search results
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No results for \"\(searchText)\"")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(displayedContacts) { contact in
                                    NavigationLink(destination: ContactDetailView(contact: contact)) {
                                        ContactRow(contact: contact)
                                    }
                                    .onAppear {
                                        if contact.id == displayedContacts.last?.id, searchText.isEmpty {
                                            Task { await viewModel.loadMoreContacts() }
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if showHiddenContacts {
                                            Button {
                                                Task { await unhideContact(contact) }
                                            } label: {
                                                Label("Unhide", systemImage: "eye")
                                            }
                                            .tint(.green)
                                        } else {
                                            Button {
                                                Task { await hideContact(contact) }
                                            } label: {
                                                Label("Hide", systemImage: "eye.slash")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                }
                                .onDelete(perform: deleteContacts)

                                if viewModel.hasMoreContacts, searchText.isEmpty {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(showHiddenContacts ? "Hidden Contacts" : localizationService.t("nav.contacts"))
            .searchable(text: $searchText, prompt: localizationService.t("contacts.search"))
            .onChange(of: searchText) { newValue in
                performSearch(query: newValue)
            }
            .onAppear {
                Task {
                    if showHiddenContacts {
                        await viewModel.loadHiddenContacts()
                    } else {
                        await viewModel.loadContacts()
                    }
                }
            }
            .refreshable {
                await viewModel.loadContacts()
                await viewModel.sync()
            }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            searchResults = await viewModel.searchContacts(query: query)
            isSearching = false
        }
    }

    private func deleteContacts(at offsets: IndexSet) {
        let contactsToDelete = offsets.map { displayedContacts[$0] }
        for contact in contactsToDelete {
            Task {
                do {
                    try await viewModel.removeContact(id: contact.id)
                } catch {
                    viewModel.showError("Failed to Delete", message: "Could not remove \(contact.displayName): \(error.localizedDescription)")
                }
            }
        }
    }

    private func toggleHiddenContactsMode() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Toggle mode
        showHiddenContacts.toggle()

        // Clear search when switching modes
        searchText = ""

        // Load appropriate contacts
        Task {
            if showHiddenContacts {
                await viewModel.loadHiddenContacts()
            } else {
                await viewModel.loadContacts()
            }
        }
    }

    private func hideContact(_ contact: ContactInfo) async {
        do {
            try await viewModel.hideContact(id: contact.id)
        } catch {
            viewModel.showError("Failed to Hide", message: "Could not hide \(contact.displayName): \(error.localizedDescription)")
        }
    }

    private func unhideContact(_ contact: ContactInfo) async {
        do {
            try await viewModel.unhideContact(id: contact.id)
        } catch {
            viewModel.showError("Failed to Unhide", message: "Could not unhide \(contact.displayName): \(error.localizedDescription)")
        }
    }
}

struct ContactRow: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let contact: ContactInfo
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        HStack(spacing: 12) {
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

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    if contact.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .accessibilityIdentifier("contacts.verified")
                    }
                    Text(contact.verified ? localizationService.t("contacts.verified") : localizationService.t("contacts.not_verified"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Delivery status indicator
                    if let status = viewModel.getLatestDeliveryStatusForContact(contactId: contact.id) {
                        Spacer()
                        DeliveryStatusIndicator(status: status)
                    }
                }
            }

            Spacer()

            // Field count if available
            if let card = contact.card, !card.fields.isEmpty {
                Text("\(card.fields.count) field\(card.fields.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("contacts.row")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contact.displayName), \(contact.verified ? "verified" : "not verified")")
        .accessibilityHint("Double tap to view contact details")
    }
}

struct EmptyContactsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        VStack(spacing: 20) {
            // Show demo contact if available
            if let demo = viewModel.demoContact {
                DemoContactCard(demo: demo)
                    .padding(.horizontal)

                Divider()
                    .padding(.vertical)
            }

            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(localizationService.t("contacts.empty"))
                .font(.title2)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)

            Text("Exchange with someone to add them as a contact")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            NavigationLink(destination: ExchangeTabView()) {
                Label(localizationService.t("exchange.title"), systemImage: "qrcode")
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .accessibilityLabel("Start Exchange")
            .accessibilityHint("Opens the QR code exchange screen to add your first contact")
        }
        .accessibilityIdentifier("contacts.empty")
    }
}

// MARK: - Demo Contact Card

// Based on: features/demo_contact.feature

struct DemoContactCard: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let demo: VauchiDemoContact

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(demo.displayName)
                            .font(.headline)

                        Text("Demo")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .cornerRadius(4)
                    }

                    Text(demo.tipCategory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Dismiss button
                Button(action: {
                    Task {
                        try? await viewModel.dismissDemoContact()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss demo contact")
            }

            // Tip content
            VStack(alignment: .leading, spacing: 8) {
                Text(demo.tipTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(demo.tipContent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Info text
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("This is a demo contact showing how Vauchi updates work")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .accessibilityIdentifier("contacts.demo")
    }
}

/// Wrapper to navigate to exchange tab
struct ExchangeTabView: View {
    var body: some View {
        ExchangeView()
    }
}

#Preview {
    ContactsView()
        .environmentObject(VauchiViewModel())
}
