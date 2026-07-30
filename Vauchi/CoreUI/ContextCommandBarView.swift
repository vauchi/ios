// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContextCommandBarView: View {
    let surfaceID: String
    let bar: PresentationContextBar?
    let windowClass: PresentationWindowClass
    let onEvent: (PresentationEvent) -> Void

    var body: some View {
        HStack(spacing: 8) {
            roleButton(bar?.back, systemImage: "chevron.left")
            roleButton(bar?.navigation, systemImage: "line.3.horizontal")
            primaryButton
            roleButton(bar?.secondary, systemImage: "ellipsis")
        }
        .padding(8)
        .frame(maxWidth: windowClass == .compact ? .infinity : 620)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contextual commands")
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let primary = bar?.primary {
            Button(primary.label) {
                activate(primary)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: 48)
            .disabled(!primary.enabled)
            .accessibilityLabel(primary.accessibilityLabel)
            .keyboardShortcut(
                primary.shortcut == .undo ? "z" : .return,
                modifiers: .command
            )
        } else {
            Spacer()
                .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    @ViewBuilder
    private func roleButton(
        _ action: PresentationAction?,
        systemImage: String
    ) -> some View {
        if let action {
            Button {
                activate(action)
            } label: {
                Image(systemName: systemImage)
                    .frame(width: 44, height: 44)
            }
            .disabled(!action.enabled)
            .accessibilityLabel(action.accessibilityLabel)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func activate(_ action: PresentationAction) {
        onEvent(
            .actionActivated(
                surfaceID: surfaceID,
                interactionID: action.interactionID
            )
        )
    }
}
