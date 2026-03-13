// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// InlineConfirmView.swift
// Renders an InlineConfirm component from core UI (iOS)

import SwiftUI

/// Renders a core `Component::InlineConfirm` as an inline warning with confirm/cancel buttons.
struct InlineConfirmView: View {
    let component: InlineConfirmComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(component.warning)
                .font(.callout)
                .foregroundColor(component.destructive ? .red : .primary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    onAction(.actionPressed(actionId: "\(component.id):cancel"))
                } label: {
                    Text(component.cancelText)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(component.cancelText)

                Button {
                    onAction(.actionPressed(actionId: "\(component.id):confirm"))
                } label: {
                    Text(component.confirmText)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(component.destructive ? Color.red : Color.cyan)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(component.confirmText)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
}
