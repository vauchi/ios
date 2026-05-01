// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CardPreviewView.swift
// Renders a CardPreview component from core UI

import CoreUIModels
import SwiftUI

/// Renders a core `Component::CardPreview` as a styled card with group views.
struct CardPreviewView: View {
    let component: CardPreviewComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    /// Dynamic-Type-aware avatar-initial font size, tied to `.title` since
    /// the contact-card avatar circle is smaller than `AvatarPreviewView`'s.
    @ScaledMetric(relativeTo: .title) private var avatarInitialSize: CGFloat = 36

    var body: some View {
        VStack(spacing: 16) {
            // Group selector (if groups exist)
            if !component.groupViews.isEmpty {
                groupSelector
            }

            // Card
            cardView
        }
    }

    private var groupSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" tab
                groupTab(name: "All", isSelected: component.selectedGroup == nil) {
                    onAction(.groupViewSelected(groupName: nil))
                }

                ForEach(component.groupViews) { groupView in
                    groupTab(
                        name: groupView.groupName,
                        isSelected: component.selectedGroup == groupView.groupName
                    ) {
                        onAction(.groupViewSelected(groupName: groupView.groupName))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func groupTab(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.cyan : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(CGFloat(tokens.borderRadius.lg))
        }
        .accessibilityLabel(name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var cardView: some View {
        VStack(spacing: 0) {
            // Card header
            VStack(spacing: 8) {
                avatarCircle
                    .accessibilityHidden(true)

                Text(currentDisplayName)
                    .font(Font.title2.weight(.semibold))
                    .accessibilityLabel("Display name: \(currentDisplayName)")
            }
            .padding(.vertical, 24)

            Divider()

            // Fields
            VStack(spacing: 0) {
                let fields = currentFields
                if fields.isEmpty {
                    Text("No fields visible")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(fields) { field in
                        CardFieldRow(field: field)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.lg))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .accessibilityLabel(component.a11y?.label ?? "Card preview: \(component.name)")
        .accessibilityHint(component.a11y?.hint ?? "")
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let avatarData = component.avatarData,
           let uiImage = UIImage(data: Data(avatarData)) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Text(currentDisplayName.prefix(1).uppercased())
                        .font(.system(size: avatarInitialSize, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .foregroundColor(.white)
                )
        }
    }

    private var currentDisplayName: String {
        if let selectedGroup = component.selectedGroup,
           let groupView = component.groupViews.first(where: { $0.groupName == selectedGroup }) {
            return groupView.displayName
        }
        return component.name
    }

    private var currentFields: [FieldDisplay] {
        // Core's `build_visible_fields` does the selectedGroup branch + the
        // visibility filter identically across frontends. Render the
        // pre-computed list directly — no fallback. Test fixtures are part
        // of the contract: they must populate `visibleFields:` matching
        // what core emits. ADR-021 / ADR-043 (Humble UI).
        component.visibleFields
    }
}

struct CardFieldRow: View {
    let field: FieldDisplay

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForFieldType(field.fieldType))
                .foregroundColor(.cyan)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(field.value)
                    .font(.body)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(field.label): \(field.value)")
    }

    private func iconForFieldType(_ type: String) -> String {
        switch type.lowercased() {
        case "phone": "phone"
        case "email": "envelope"
        case "website": "globe"
        case "address": "mappin"
        case "social": "at"
        case "birthday": "gift"
        default: "doc.text"
        }
    }
}
