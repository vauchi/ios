// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PresentationSurfaceView: View {
    let surface: PresentationSurface
    let active: Bool
    let useFrontCamera: Bool
    let onCameraPermissionDenied: () -> Void
    let focusedBinding: FocusState<String?>.Binding
    let onEvent: (PresentationEvent) -> Void

    var body: some View {
        Group {
            if surface.layout == .scroll {
                ScrollView {
                    content
                }
            } else {
                content
            }
        }
        .padding(CGFloat(surface.tokens.spacingLarge))
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(
            RoundedRectangle(cornerRadius: CGFloat(surface.tokens.cornerRadius))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(surface.tokens.cornerRadius))
                .stroke(
                    active ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                // Simultaneous so it still fires when a child handles the
                // tap: focus must leave the field whatever was pressed,
                // otherwise SwiftUI keeps it and Core never hears that the
                // user moved on. Tapping the focused field itself clears
                // and re-takes focus, so one spurious InputFocusEnded can
                // precede the refocus.
                focusedBinding.wrappedValue = nil
                onEvent(.surfaceActivated(surfaceID: surface.surfaceID))
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(surface.accessibilityLabel)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CGFloat(surface.tokens.spacingMedium)) {
            Text(surface.title)
                .font(.title2.bold())
            if let subtitle = surface.subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            ForEach(identifyPresentationNodes(surface.nodes)) { identified in
                PresentationNodeView(
                    node: identified.node,
                    surfaceID: surface.surfaceID,
                    minimumTarget: CGFloat(surface.tokens.minimumTargetSize),
                    useFrontCamera: useFrontCamera,
                    onCameraPermissionDenied: onCameraPermissionDenied,
                    focusedBinding: focusedBinding,
                    onEvent: onEvent
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
