// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SocialGraphView.swift
// Visual representation of contact network with trust levels
// Part of: SP-20 Social Network

import SwiftUI
import VauchiPlatform

// MARK: - Trust Level

/// Display properties for core's 4-tier trust level (ADR-021/034).
/// Mapped from `MobileContactTrustLevel` — never re-derived from booleans.
enum ContactTrustLevel: Comparable {
    case cautious
    case standard
    case high
    case verified

    init(from mobile: MobileContactTrustLevel) {
        switch mobile {
        case .cautious: self = .cautious
        case .standard: self = .standard
        case .high: self = .high
        case .verified: self = .verified
        }
    }

    var displayName: String {
        switch self {
        case .cautious: "Needs Re-verification"
        case .standard: "Not Verified"
        case .high: "High Trust"
        case .verified: "Verified"
        }
    }

    var iconName: String {
        switch self {
        case .cautious: "exclamationmark.triangle.fill"
        case .standard: "person.crop.circle.badge.questionmark"
        case .high: "checkmark.shield.fill"
        case .verified: "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .cautious: .orange
        case .standard: .secondary
        case .high: .blue
        case .verified: .green
        }
    }

    var sectionFooter: String {
        switch self {
        case .cautious:
            "These contacts recovered their identity. Verify them again before trusting sensitive information."
        case .standard:
            "Consider verifying these contacts' fingerprints in person for stronger security."
        case .high:
            "These contacts were verified via proximity (NFC or Bluetooth)."
        case .verified:
            "You have verified these contacts' identities in person."
        }
    }
}

// MARK: - Social Graph View

/// List-based view showing contacts organized by trust level
///
/// Displays the user's contact network with trust information,
/// verification status, and group memberships. Uses a sectioned list
/// approach (not complex graph rendering) for clarity and accessibility.
struct SocialGraphView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

    @State private var contactGroupMap: [String: [VauchiVisibilityLabel]] = [:]
    @State private var isLoading = true
    @State private var filterTrustLevel: ContactTrustLevel?

    /// Contacts grouped by core's authoritative trust level
    private func contactsAt(_ level: ContactTrustLevel) -> [ContactInfo] {
        filteredContacts.filter { ContactTrustLevel(from: $0.trustLevel) == level }
    }

    private var filteredContacts: [ContactInfo] {
        guard let filter = filterTrustLevel else {
            return viewModel.contacts
        }
        return viewModel.contacts.filter { ContactTrustLevel(from: $0.trustLevel) == filter }
    }

    /// Summary statistics
    private var totalContacts: Int {
        viewModel.contacts.count
    }

    private var verifiedCount: Int {
        viewModel.contacts.filter {
            let t = ContactTrustLevel(from: $0.trustLevel)
            return t == .verified || t == .high
        }.count
    }

    private var cautionsCount: Int {
        contactsAt(.cautious).count
    }

    private var groupCount: Int {
        viewModel.visibilityLabels.count
    }

    /// Trust levels in display order: cautious first (needs attention),
    /// then ascending trust (standard → high → verified).
    private let trustLevelOrder: [ContactTrustLevel] = [
        .cautious, .standard, .high, .verified
    ]

    var body: some View {
        List {
            // Network summary card
            Section {
                NetworkSummaryCard(
                    totalContacts: totalContacts,
                    verifiedCount: verifiedCount,
                    cautionsCount: cautionsCount,
                    groupCount: groupCount
                )
            }

            // Trust level filter
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TrustFilterChip(
                            label: "All",
                            count: totalContacts,
                            color: .cyan,
                            isSelected: filterTrustLevel == nil
                        ) {
                            filterTrustLevel = nil
                        }

                        ForEach(trustLevelOrder, id: \.self) { level in
                            let count = contactsAt(level).count
                            if count > 0 || filterTrustLevel == level {
                                TrustFilterChip(
                                    label: level.displayName,
                                    count: count,
                                    color: level.color,
                                    isSelected: filterTrustLevel == level
                                ) {
                                    filterTrustLevel = filterTrustLevel == level ? nil : level
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            // Contact sections by trust level
            ForEach(trustLevelOrder, id: \.self) { level in
                let contacts = contactsAt(level)
                if !contacts.isEmpty {
                    Section {
                        ForEach(contacts) { contact in
                            NavigationLink(destination: ContactDetailView(contact: contact)) {
                                SocialContactRow(
                                    contact: contact,
                                    trustLevel: level,
                                    groups: contactGroupMap[contact.id] ?? []
                                )
                            }
                        }
                    } header: {
                        TrustSectionHeader(
                            title: level.displayName,
                            icon: level.iconName,
                            color: level.color,
                            count: contacts.count
                        )
                    } footer: {
                        Text(level.sectionFooter)
                    }
                }
            }

            // Empty state
            if viewModel.contacts.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text("No contacts yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Exchange with someone to start building your network.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("Contact Network")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadContactGroups()
        }
        .refreshable {
            await loadContactGroups()
        }
    }

    private func loadContactGroups() async {
        isLoading = true
        await viewModel.loadLabels()

        var map: [String: [VauchiVisibilityLabel]] = [:]
        for contact in viewModel.contacts {
            do {
                let labels = try viewModel.getLabelsForContact(contactId: contact.id)
                if !labels.isEmpty {
                    map[contact.id] = labels
                }
            } catch {
                // Labels are optional -- silently skip on error
            }
        }
        contactGroupMap = map
        isLoading = false
    }
}

// MARK: - Supporting Views

/// Summary card showing network statistics
struct NetworkSummaryCard: View {
    let totalContacts: Int
    let verifiedCount: Int
    let cautionsCount: Int
    let groupCount: Int

    private var verificationPercentage: Int {
        guard totalContacts > 0 else { return 0 }
        return Int(Double(verifiedCount) / Double(totalContacts) * 100)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.cyan)
                    .accessibilityHidden(true)
                Text("Your Network")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 0) {
                NetworkStatItem(
                    value: "\(totalContacts)",
                    label: "Contacts",
                    icon: "person.2",
                    color: .cyan
                )

                Divider()
                    .frame(height: 40)

                NetworkStatItem(
                    value: "\(verificationPercentage)%",
                    label: "Trusted",
                    icon: "checkmark.seal",
                    color: .green
                )

                Divider()
                    .frame(height: 40)

                if cautionsCount > 0 {
                    NetworkStatItem(
                        value: "\(cautionsCount)",
                        label: "Caution",
                        icon: "exclamationmark.triangle",
                        color: .orange
                    )

                    Divider()
                        .frame(height: 40)
                }

                NetworkStatItem(
                    value: "\(groupCount)",
                    label: "Groups",
                    icon: "person.3",
                    color: .purple
                )
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Network summary: \(totalContacts) contacts, \(verificationPercentage) percent trusted, \(cautionsCount) need re-verification, \(groupCount) groups")
    }
}

/// Single stat item in the network summary
struct NetworkStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
                .accessibilityHidden(true)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Filter chip for trust level filtering
struct TrustFilterChip: View {
    let label: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? color : Color(.systemGray5))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .accessibilityLabel("\(label): \(count)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to \(isSelected ? "remove" : "apply") filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Section header for trust level groups
struct TrustSectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
                .accessibilityHidden(true)
            Text(title)
            Text("(\(count))")
                .foregroundColor(.secondary)
        }
    }
}

/// Contact row in the social graph, showing trust level and group badges
struct SocialContactRow: View {
    let contact: ContactInfo
    let trustLevel: ContactTrustLevel
    let groups: [VauchiVisibilityLabel]

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with trust indicator
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(trustLevel.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text(String(contact.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(trustLevel.color)
                }

                // Trust badge
                Image(systemName: trustLevel.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(trustLevel.color)
                    .background(
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 16, height: 16)
                    )
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: trustLevel.iconName)
                        .foregroundColor(trustLevel.color)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(trustLevel.displayName)
                        .font(.caption)
                        .foregroundColor(trustLevel.color)
                }

                // Group badges (inline)
                if !groups.isEmpty {
                    ContactGroupBadges(groups: groups, compact: true)
                }
            }

            Spacer()

            // Fingerprint snippet
            if !contact.fingerprint.isEmpty {
                Text(String(contact.fingerprint.prefix(8)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Fingerprint starts with \(String(contact.fingerprint.prefix(8)))")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contact.displayName), \(trustLevel.displayName)\(groups.isEmpty ? "" : ", in \(groups.count) group\(groups.count == 1 ? "" : "s")")")
        .accessibilityHint("Double tap to view contact details")
    }
}

#Preview {
    NavigationView {
        SocialGraphView()
    }
    .environmentObject(VauchiViewModel())
}
