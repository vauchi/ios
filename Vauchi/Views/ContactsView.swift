// ContactsView.swift
// Contact list view with search

import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [ContactInfo] = []

    private var displayedContacts: [ContactInfo] {
        if searchText.isEmpty {
            return viewModel.contacts
        } else {
            return searchResults
        }
    }

    private var contactCount: Int {
        viewModel.contacts.count
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.contacts.isEmpty && searchText.isEmpty {
                    EmptyContactsView()
                } else {
                    VStack(spacing: 0) {
                        // Contact count header
                        if !searchText.isEmpty || !viewModel.contacts.isEmpty {
                            HStack {
                                Text("\(contactCount) contact\(contactCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.systemGroupedBackground))
                        }

                        if displayedContacts.isEmpty && !searchText.isEmpty {
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
                                }
                                .onDelete(perform: deleteContacts)
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Contacts")
            .searchable(text: $searchText, prompt: "Search contacts")
            .onChange(of: searchText) { newValue in
                performSearch(query: newValue)
            }
            .onAppear {
                Task { await viewModel.loadContacts() }
            }
            .refreshable {
                await viewModel.loadContacts()
                await viewModel.sync()
            }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) { }
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
}

struct ContactRow: View {
    let contact: ContactInfo

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
                    }
                    Text(contact.verified ? "Verified" : "Not verified")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    }
}

struct EmptyContactsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No contacts yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Exchange with someone to add them as a contact")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            NavigationLink(destination: ExchangeTabView()) {
                Label("Start Exchange", systemImage: "qrcode")
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }
}

// Wrapper to navigate to exchange tab
struct ExchangeTabView: View {
    var body: some View {
        ExchangeView()
    }
}

#Preview {
    ContactsView()
        .environmentObject(VauchiViewModel())
}
