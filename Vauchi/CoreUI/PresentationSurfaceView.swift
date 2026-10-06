// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PresentationSurfaceView: View {
    let surface: PresentationSurface
    let active: Bool
    let bar: PresentationContextBar?
    let navigationShown: Bool
    let useFrontCamera: Bool
    let onCameraPermissionDenied: () -> Void
    let focusedBinding: FocusState<String?>.Binding
    let onEvent: (PresentationEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(surface.tokens.spacingMedium)) {
            SurfaceTitleBarView(
                surfaceID: surface.surfaceID,
                title: surface.title,
                bar: bar,
                navigationShown: navigationShown,
                minimumTarget: CGFloat(surface.tokens.minimumTargetSize),
                onEvent: onEvent
            )
            Group {
                if surface.layout.scrollsContent {
                    ScrollView {
                        content
                    }
                } else {
                    content
                        .frame(maxHeight: .infinity, alignment: .top)
                }
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

    /// Everything below the title row: Core's nodes, then `primary` (if
    /// any) at the bottom — pinned there on a `fixed` surface that cannot
    /// scroll to it, following the last row otherwise
    /// (`SurfacePrimaryButtonLayout`).
    private var content: some View {
        VStack(alignment: .leading, spacing: CGFloat(surface.tokens.spacingMedium)) {
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
            if SurfacePrimaryButtonLayout.pinsToBottom(scrollsContent: surface.layout.scrollsContent) {
                Spacer(minLength: 0)
            }
            if let primary = bar?.primary {
                SurfacePrimaryActionButtonView(
                    surfaceID: surface.surfaceID,
                    action: primary,
                    minimumTarget: CGFloat(surface.tokens.minimumTargetSize),
                    onEvent: onEvent
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
