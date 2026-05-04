// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// PreviewView.swift
// Renders a Preview component from core UI (Wire Humble — variants
// replace the old contact-specific group views).

import CoreUIModels
import SwiftUI

/// Renders a core `Component::Preview` as a styled card with optional
/// variant tabs. The renderer doesn't know what kind of thing the
/// preview represents — engines populate `variants` with whatever
/// alternate looks make sense (group views today; per-locale, per-
/// relationship, etc. tomorrow).
struct PreviewView: View {
    let component: PreviewComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

    /// Dynamic-Type-aware avatar-initial font size, tied to `.title` since
    /// the preview avatar circle is smaller than `AvatarPreviewView`'s.
    @ScaledMetric(relativeTo: .title) private var avatarInitialSize: CGFloat = 36

    var body: some View {
        VStack(spacing: 16) {
            // Variant selector (if alternate views exist)
            if !component.variants.isEmpty {
                variantSelector
            }

            // Card
            cardView
        }
    }

    private var variantSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" tab
                variantTab(name: "All", isSelected: component.selectedVariant == nil) {
                    onAction(.groupViewSelected(groupName: nil))
                }

                ForEach(component.variants) { variant in
                    variantTab(
                        name: variant.displayName,
                        isSelected: component.selectedVariant == variant.variantId
                    ) {
                        onAction(.groupViewSelected(groupName: variant.variantId))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func variantTab(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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
                        PreviewFieldRow(field: field)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.lg))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .accessibilityLabel(component.a11y?.label ?? "Preview: \(component.name)")
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
        if let selectedVariant = component.selectedVariant,
           let variant = component.variants.first(where: { $0.variantId == selectedVariant }) {
            return variant.displayName
        }
        return component.name
    }

    private var currentFields: [Field] {
        // Core's `build_visible_fields` does the selectedVariant branch + the
        // visibility filter identically across frontends. Render the
        // pre-computed list directly — no fallback. Test fixtures are part
        // of the contract: they must populate `visibleFields:` matching
        // what core emits. ADR-021 / ADR-043 (Humble UI).
        component.visibleFields
    }
}

struct PreviewFieldRow: View {
    let field: Field

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
