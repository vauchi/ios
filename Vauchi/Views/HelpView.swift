// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// HelpView.swift
// FAQ and help view

import SwiftUI
import VauchiMobile

struct HelpView: View {
    @State private var searchQuery = ""
    @State private var selectedCategory: MobileHelpCategory?
    @State private var expandedFaqId: String?

    private let categories = getHelpCategories()
    private let allFaqs = getFaqs()

    var body: some View {
        List {
            // Search section
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search FAQs", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("help.search")

            // Show search results or categories
            if !searchQuery.isEmpty {
                searchResultsSection
            } else if let category = selectedCategory {
                categoryFaqsSection(category)
            } else {
                categoriesSection
            }
        }
        .navigationTitle(LocalizationService.shared.t("help.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    /// Categories list
    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(categories, id: \.category) { categoryInfo in
                Button(action: { selectedCategory = categoryInfo.category }) {
                    HStack {
                        Image(systemName: iconForCategory(categoryInfo.category))
                            .frame(width: 24)
                            .foregroundColor(.accentColor)

                        Text(categoryInfo.displayName)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(faqCountForCategory(categoryInfo.category))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("help.category.\(categoryInfo.displayName)")
            }
        }
    }

    /// FAQs for a specific category
    private func categoryFaqsSection(_ category: MobileHelpCategory) -> some View {
        Section {
            // Back button
            Button(action: { selectedCategory = nil }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("All Categories")
                }
                .foregroundColor(.accentColor)
            }

            // Category FAQs
            ForEach(getFaqsByCategory(category: category), id: \.id) { faq in
                FaqRow(
                    faq: faq,
                    isExpanded: expandedFaqId == faq.id,
                    onToggle: { toggleFaq(faq.id) }
                )
            }
        } header: {
            Text(displayNameForCategory(category))
        }
    }

    /// Search results section
    private var searchResultsSection: some View {
        Section {
            let results = searchFaqs(query: searchQuery)

            if results.isEmpty {
                Text("No results found for \"\(searchQuery)\"")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(results, id: \.id) { faq in
                    FaqRow(
                        faq: faq,
                        isExpanded: expandedFaqId == faq.id,
                        onToggle: { toggleFaq(faq.id) }
                    )
                }
            }
        } header: {
            Text("Search Results (\(searchFaqs(query: searchQuery).count))")
        }
    }

    // MARK: - Helpers

    private func toggleFaq(_ id: String) {
        withAnimation {
            if expandedFaqId == id {
                expandedFaqId = nil
            } else {
                expandedFaqId = id
            }
        }
    }

    private func faqCountForCategory(_ category: MobileHelpCategory) -> Int {
        allFaqs.filter { $0.category == category }.count
    }

    private func displayNameForCategory(_ category: MobileHelpCategory) -> String {
        categories.first { $0.category == category }?.displayName ?? ""
    }

    private func iconForCategory(_ category: MobileHelpCategory) -> String {
        switch category {
        case .gettingStarted: return "star"
        case .privacy: return "lock.shield"
        case .recovery: return "arrow.counterclockwise"
        case .contacts: return "person.2"
        case .updates: return "arrow.triangle.2.circlepath"
        case .features: return "sparkles"
        }
    }
}

/// Row displaying a FAQ item
struct FaqRow: View {
    let faq: MobileFaqItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .top) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    Text(faq.question)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityIdentifier("help.faq.\(faq.id)")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                Text(faq.answer)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
                    .padding(.top, 4)

                // Related FAQs
                if !faq.related.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Related:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        ForEach(faq.related, id: \.self) { relatedId in
                            if let relatedFaq = getFaqById(id: relatedId) {
                                Text("• \(relatedFaq.question)")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .padding(.leading, 32)
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        HelpView()
    }
}
