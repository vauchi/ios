// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// InfoPanelView.swift
// Renders an InfoPanel component from core UI

import CoreUIModels
import SwiftUI

/// Renders a core `Component::InfoPanel` as a styled list of info items.
struct InfoPanelView: View {
    let component: InfoPanelComponent
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(tokens.spacing.md)) {
            // Panel header
            HStack(spacing: CGFloat(tokens.spacing.smMd)) {
                if let icon = component.icon {
                    Image(systemName: sfSymbolForCoreIcon(icon))
                        .font(.system(size: 24))
                        .foregroundColor(.cyan)
                        .accessibilityHidden(true)
                }

                Text(component.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            // Items
            VStack(spacing: CGFloat(tokens.spacing.smMd)) {
                ForEach(component.items) { item in
                    InfoItemRow(item: item)
                }
            }
        }
        .padding(CGFloat(tokens.spacing.md))
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityLabel(component.a11y?.label ?? component.title)
        .accessibilityHint(component.a11y?.hint ?? "")
        .accessibilityAddTraits(.isHeader)
    }
}

struct InfoItemRow: View {
    let item: InfoItem

    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(tokens.spacing.md)) {
            if let icon = item.icon {
                Image(systemName: sfSymbolForCoreIcon(icon))
                    .font(.system(size: 20))
                    .foregroundColor(.cyan)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Maps core icon names to SF Symbols.
///
/// Core uses generic icon names; this function maps them to platform-native symbols.
func sfSymbolForCoreIcon(_ name: String) -> String {
    switch name {
    case "lock": "lock.fill"
    case "refresh": "arrow.triangle.2.circlepath"
    case "people": "person.2.fill"
    case "shield": "shield.fill"
    case "server": "server.rack"
    case "key": "key.fill"
    case "backup": "externaldrive.fill"
    case "warning": "exclamationmark.triangle.fill"
    case "devices": "laptopcomputer.and.iphone"
    case "check": "checkmark.circle.fill"
    case "share": "square.and.arrow.up"
    case "edit": "pencil"
    case "group": "person.3.fill"
    case "card": "person.crop.rectangle"
    case "eye": "eye.fill"
    case "visibility_off": "eye.slash.fill"
    default: "info.circle"
    }
}
