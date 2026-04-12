// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// BannerView.swift
// Renders a Banner component from core UI

import SwiftUI

/// Renders a core `Component::Banner` as an informational banner with an action button.
struct BannerView: View {
    let component: BannerComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        HStack {
            Text(component.text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button(component.actionLabel) {
                onAction(.actionPressed(actionId: component.actionId))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.accentColor)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(component.a11y?.label ?? component.text)
        .accessibilityHint(component.a11y?.hint ?? "")
    }
}
