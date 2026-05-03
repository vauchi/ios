// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactGroupBadges.swift
// Inline badges showing which groups a contact belongs to
// Part of: SP-20 Social Network

import SwiftUI
import VauchiPlatform

/// Displays small tappable badges showing group/label membership for a contact.
///
/// Used on contact rows and contact detail views to show at-a-glance
/// which groups (visibility labels) a contact belongs to.
///
/// - `compact`: When true, shows up to 2 badges with a "+N" overflow.
///   When false, shows all badges in a wrapping flow layout.
struct ContactGroupBadges: View {
    let groups: [VauchiVisibilityLabel]
    var compact: Bool = false
    var onGroupTap: ((VauchiVisibilityLabel) -> Void)?

    /// Maximum badges to show in compact mode before showing "+N"
    private let compactLimit = 2

    private var displayedGroups: [VauchiVisibilityLabel] {
        if compact, groups.count > compactLimit {
            return Array(groups.prefix(compactLimit))
        }
        return groups
    }

    private var overflowCount: Int {
        if compact, groups.count > compactLimit {
            return groups.count - compactLimit
        }
        return 0
    }

    var body: some View {
        if groups.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(displayedGroups) { group in
                    GroupBadge(
                        name: group.name,
                        onTap: onGroupTap.map { tap in
                            { tap(group) }
                        }
                    )
                }

                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(Font.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                        .accessibilityLabel("\(overflowCount) more group\(overflowCount == 1 ? "" : "s")")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Groups: \(groups.map(\.name).joined(separator: ", "))")
        }
    }
}

/// A single group badge pill
struct GroupBadge: View {
    let name: String
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                badgeContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) group")
            .accessibilityHint("Double tap to view group details")
        } else {
            badgeContent
                .accessibilityLabel("\(name) group")
        }
    }

    private var badgeContent: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8))
                .accessibilityHidden(true)
            Text(name)
                .font(Font.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundColor(.cyan)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.cyan.opacity(0.12))
        .cornerRadius(4)
    }
}

/// A view that loads and displays group badges for a contact by ID.
///
/// This is a convenience wrapper that fetches the contact's groups
/// from the ViewModel and displays them as badges. Use this when
/// you only have a contact ID and want to show their group membership.
struct ContactGroupBadgesLoader: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    let contactId: String
    var compact: Bool = false
    var onGroupTap: ((VauchiVisibilityLabel) -> Void)?

    @State private var groups: [VauchiVisibilityLabel] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded, !groups.isEmpty {
                ContactGroupBadges(
                    groups: groups,
                    compact: compact,
                    onGroupTap: onGroupTap
                )
            }
        }
        .task {
            loadGroups()
        }
    }

    private func loadGroups() {
        do {
            groups = try viewModel.getLabelsForContact(contactId: contactId)
        } catch {
            groups = []
        }
        hasLoaded = true
    }
}

#Preview("Multiple badges") {
    ContactGroupBadges(
        groups: [
            VauchiVisibilityLabel(
                id: "1", name: "Family",
                contactCount: 5, visibleFieldCount: 3,
                createdAt: 0, modifiedAt: 0
            ),
            VauchiVisibilityLabel(
                id: "2", name: "Friends",
                contactCount: 12, visibleFieldCount: 2,
                createdAt: 0, modifiedAt: 0
            ),
            VauchiVisibilityLabel(
                id: "3", name: "Work",
                contactCount: 8, visibleFieldCount: 4,
                createdAt: 0, modifiedAt: 0
            ),
        ],
        compact: true
    )
    .padding()
}

#Preview("Single badge") {
    ContactGroupBadges(
        groups: [
            VauchiVisibilityLabel(
                id: "1", name: "Family",
                contactCount: 5, visibleFieldCount: 3,
                createdAt: 0, modifiedAt: 0
            ),
        ]
    )
    .padding()
}
