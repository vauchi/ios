// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CardPreviewView.swift
// Renders a CardPreview component from core UI

import SwiftUI

/// Renders a core `Component::CardPreview` as a styled card with group views.
struct CardPreviewView: View {
    let component: CardPreviewComponent
    let onAction: (UserAction) -> Void

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
                .cornerRadius(20)
        }
        .accessibilityLabel(name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var cardView: some View {
        VStack(spacing: 0) {
            // Card header
            VStack(spacing: 8) {
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
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .accessibilityHidden(true)

                Text(currentDisplayName)
                    .font(.title2)
                    .fontWeight(.semibold)
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
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }

    private var currentDisplayName: String {
        if let selectedGroup = component.selectedGroup,
           let groupView = component.groupViews.first(where: { $0.groupName == selectedGroup }) {
            return groupView.displayName
        }
        return component.name
    }

    private var currentFields: [FieldDisplay] {
        if let selectedGroup = component.selectedGroup,
           let groupView = component.groupViews.first(where: { $0.groupName == selectedGroup }) {
            return groupView.visibleFields
        }
        return component.fields.filter { field in
            if case .shown = field.visibility { return true }
            if case .groups = field.visibility { return true }
            return false
        }
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
