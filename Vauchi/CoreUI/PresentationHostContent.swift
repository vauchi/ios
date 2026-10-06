// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The visible composition of one `PresentationState`: surfaces (each
/// drawing its own title row from Core's context bar), persistent tab bar
/// and any overlay. `PresentationHostView` wraps it with the live view
/// model, gestures and sheets; the screen-catalog render replays a state
/// through it without an engine.
struct PresentationHostContent: View {
    let state: PresentationState
    let useFrontCamera: Bool
    let onCameraPermissionDenied: () -> Void
    let onEvent: (_ surfaceID: String, _ event: PresentationEvent) -> Void
    let onDismissOverlay: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @FocusState private var focusedBindingID: String?

    var body: some View {
        ZStack {
            surfaces
                .padding(profileClass == .compact ? 0 : 16)
                .safeAreaInset(edge: .bottom) {
                    navigationBar
                }
            if let overlay = state.activeOverlay {
                // Dismiss before dispatch: Core clears its own open-overlay
                // state only on `OverlayDismissed`, so reporting the choice
                // first keeps this surface the active one for fail-closed
                // validation.
                PresentationOverlayView(
                    overlay: overlay,
                    windowClass: profileClass,
                    reducedMotion: reducedMotion,
                    onAction: { event in
                        onDismissOverlay()
                        onEvent(overlay.surfaceID, event)
                    },
                    onDismiss: onDismissOverlay
                )
                .zIndex(20)
            }
        }
    }

    private var profileClass: PresentationWindowClass {
        state.profile?.windowClass ?? .compact
    }

    @ViewBuilder
    private var surfaces: some View {
        let ids = state.visibleSurfaceIDs
        if state.profile?.paneLayout == .split {
            HStack(spacing: 16) {
                surfaceViews(ids)
            }
        } else {
            VStack {
                surfaceViews(ids)
            }
        }
    }

    private func surfaceViews(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { surfaceID in
            if let surface = state.surfaces[surfaceID] {
                PresentationSurfaceView(
                    surface: surface,
                    active: state.activeSurfaceID == surfaceID,
                    bar: state.bars[surfaceID]?.bar,
                    navigationShown: CoreBottomTabBarLayout.isVisible(
                        items: state.navigations[surfaceID]?.navigation.items ?? []
                    ),
                    useFrontCamera: useFrontCamera,
                    onCameraPermissionDenied: onCameraPermissionDenied,
                    focusedBinding: $focusedBindingID,
                    onEvent: { event in
                        onEvent(surfaceID, event)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var navigationBar: some View {
        if let surfaceID = state.activeSurfaceID,
           let items = state.activeNavigation?.navigation.items,
           CoreBottomTabBarLayout.isVisible(items: items) {
            CoreBottomTabBar(
                surfaceID: surfaceID,
                items: items,
                onEvent: { event in
                    onEvent(surfaceID, event)
                }
            )
        }
    }
}
