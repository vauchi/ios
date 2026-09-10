// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct PresentationOverlayView: View {
    let overlay: RevisionedOverlay
    let windowClass: PresentationWindowClass
    let reducedMotion: Bool
    let onAction: (PresentationEvent) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            if overlay.overlay.kind == .navigation {
                navigationOverlay
                    .transition(
                        reducedMotion
                            ? .identity
                            : .move(edge: .leading).combined(with: .opacity)
                    )
            } else {
                actionOverlay
                    .transition(
                        reducedMotion
                            ? .identity
                            : .move(edge: .bottom)
                            .combined(with: .scale(scale: 0.96))
                    )
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var navigationOverlay: some View {
        panel {
            // Core decides how many destinations it sends, so the panel
            // cannot assume they fit. Android had the same grid unscrolled
            // and silently dropped three destinations out of the hierarchy
            // entirely; the grid buys headroom here, not immunity.
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(
                                minimum: windowClass == .compact ? 120 : 180
                            )
                        ),
                    ],
                    spacing: 8
                ) {
                    actions
                }
                // Stable frontend a11y anchor for UI tests (NOT a core action
                // id): lets tests query the destination buttons without
                // coupling to localized labels.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("navigationDestinations")
            }
        }
        .frame(
            maxWidth: windowClass == .compact ? .infinity : 680,
            maxHeight: .infinity,
            alignment: .top
        )
        .padding(.top, windowClass == .compact ? 0 : 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionOverlay: some View {
        panel {
            VStack(spacing: 8) {
                actions
            }
        }
        .frame(maxWidth: windowClass == .compact ? .infinity : 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.bottom, 82)
        .padding(.horizontal, windowClass == .compact ? 0 : 20)
    }

    private func panel(
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(
                    overlay.overlay.title
                        ?? (overlay.overlay.kind == .navigation
                            ? "Navigation"
                            : "Actions")
                )
                .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            content()
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 24)
    }

    private var actions: some View {
        ForEach(overlay.overlay.items) { action in
            Button {
                onAction(
                    .actionActivated(
                        surfaceID: overlay.surfaceID,
                        interactionID: action.interactionID
                    )
                )
            } label: {
                actionLabel(action)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!action.enabled)
            .foregroundColor(action.tone.foregroundColor)
            // The icon repeats the word beside it, so it must not be its own
            // VoiceOver stop — left exposed, SwiftUI narrates the symbol and
            // gets it wrong either way: undescribed symbols read as their raw
            // identifier, and described ones get a verb chosen without any
            // context (`folder.fill` beside "Groups" says "Move";
            // `mappin.and.ellipse` beside "Places" says "Remove Map Pin",
            // naming a destructive action on a row that only navigates).
            //
            // `.accessibilityHidden` on the image does not hold: SwiftUI lifts
            // it out of the button's subtree and publishes it as a sibling,
            // where the hide no longer applies. Only replacing the whole
            // subtree with one synthetic button collapses it to a single stop.
            .accessibilityRepresentation {
                Button(action.accessibilityLabel) {}
                    .disabled(!action.enabled)
            }
        }
    }

    /// Icon *and* label, never icon alone: the symbol is a recognition aid for
    /// readers who skim rather than read, and dropping the word would trade
    /// one barrier for another.
    @ViewBuilder
    private func actionLabel(_ action: PresentationAction) -> some View {
        if let symbol = NavigationIconMap.systemImage(
            forOverlayKind: overlay.overlay.kind,
            token: action.iconToken
        ) {
            Label(action.label, systemImage: symbol)
                .labelStyle(.titleAndIcon)
        } else {
            Text(action.label)
        }
    }
}
