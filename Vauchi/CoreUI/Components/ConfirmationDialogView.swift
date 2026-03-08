// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ConfirmationDialogView.swift
// Renders a ConfirmationDialog component from core UI

import SwiftUI

/// Renders a core `Component::ConfirmationDialog` as a title, message, and action buttons.
struct ConfirmationDialogView: View {
    let component: ConfirmationDialogComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(component.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(component.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    onAction(.actionPressed(actionId: "cancel"))
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }
                .accessibilityLabel("Cancel")

                Button {
                    onAction(.actionPressed(actionId: "confirm"))
                } label: {
                    Text(component.confirmText)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(component.destructive ? Color.red : Color.cyan)
                        .cornerRadius(10)
                }
                .accessibilityLabel(component.confirmText)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
