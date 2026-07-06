// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
import SwiftUI

/// Renders a core `Component::ConfirmationDialog` as a title, message, and action buttons.
struct ConfirmationDialogView: View {
    let component: ConfirmationDialogComponent
    let onAction: (UserAction) -> Void
    @Environment(\.designTokens) private var tokens

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
                    // TODO(HUMBLE): [T, P1] frontend hardcodes generic `cancel` action id;
                    // core should supply explicit action ids in ConfirmationDialogComponent
                    // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                    onAction(.actionPressed(actionId: "cancel"))
                } label: {
                    // TODO(HUMBLE): [W, P2] hardcoded English button label
                    // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                }
                .accessibilityLabel("Cancel")

                Button {
                    // TODO(HUMBLE): [T, P1] frontend hardcodes generic `confirm` action id;
                    // core should supply explicit action ids in ConfirmationDialogComponent
                    // (see _private problem record 2026-07-06-mobile-domain-shell-violations).
                    onAction(.actionPressed(actionId: "confirm"))
                } label: {
                    Text(component.confirmText)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(component.destructive ? Color.red : Color.cyan)
                        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                }
                .accessibilityLabel(component.confirmText)
            }
        }
        .padding(CGFloat(tokens.spacing.md))
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
