// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// TextComponentView.swift
// Renders a Text component from core UI

import SwiftUI

/// Renders a core `Component::Text` with the appropriate style.
struct TextComponentView: View {
    let component: TextComponent

    var body: some View {
        Text(component.content)
            .font(font(for: component.style))
            .foregroundColor(foregroundColor(for: component.style))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(component.content)
    }

    private func font(for style: TextStyle) -> Font {
        switch style {
        case .title: .title.bold()
        case .subtitle: .title3
        case .body: .body
        case .caption: .caption
        }
    }

    private func foregroundColor(for style: TextStyle) -> Color {
        switch style {
        case .title: .primary
        case .subtitle: .secondary
        case .body: .primary
        case .caption: .secondary
        }
    }
}
