// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

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

/// Core icon token → SF Symbol map. A table (rather than a `switch`)
/// keeps the lookup at complexity 1 as the token set grows.
private let coreIconSymbols: [String: String] = [
    "lock": "lock.fill",
    "refresh": "arrow.triangle.2.circlepath",
    "people": "person.2.fill",
    "shield": "shield.fill",
    "server": "server.rack",
    "key": "key.fill",
    "backup": "externaldrive.fill",
    "warning": "exclamationmark.triangle.fill",
    "devices": "laptopcomputer.and.iphone",
    "check": "checkmark.circle.fill",
    "checkmark.circle": "checkmark.circle.fill",
    "folder": "folder.fill",
    "more": "ellipsis.circle",
    "share": "square.and.arrow.up",
    "edit": "pencil",
    "group": "person.3.fill",
    "card": "person.crop.rectangle",
    "eye": "eye.fill",
    "visibility_off": "eye.slash.fill",
    // Exchange mode glyphs (mode-selection list).
    "qrcode": "qrcode.viewfinder",
    "nfc": "wave.3.right",
    "bump": "dot.radiowaves.left.and.right",
    "shake": "iphone.radiowaves.left.and.right",
    "sparkles": "wand.and.stars",
    "tap": "hand.tap.fill",
    "gesture": "hand.draw.fill",
    "link": "link",
    "cable": "cable.connector",
    // Contact field glyphs (core `Field.icon` tokens).
    "phone": "phone.fill",
    "envelope": "envelope.fill",
    "globe": "globe",
    "mappin": "mappin",
    "at": "at",
    "gift": "gift",
    "tag": "tag.fill",
]

/// Maps core icon names to SF Symbols.
///
/// Core uses generic icon names; this function maps them to platform-native symbols.
func sfSymbolForCoreIcon(_ name: String) -> String {
    coreIconSymbols[name] ?? "info.circle"
}
