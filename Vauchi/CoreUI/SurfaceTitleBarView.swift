// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Where Core's back/navigation/secondary/info slots go in the surface's
/// own title row, kept out of the view so `SurfaceTitleBarLayoutTests` can
/// assert it without rendering. `primary` is never a title-row slot — see
/// `SurfacePrimaryButtonLayout`.
enum SurfaceTitleBarLayout {
    enum Slot: Equatable {
        case back
        case navigation
        case secondary
        case info
    }

    /// Back first, then the navigation launcher — left out while the tab
    /// bar or sidebar already shows the same destinations (vauchi/private#479).
    static func leadingSlots(bar: PresentationContextBar?, navigationShown: Bool) -> [Slot] {
        guard let bar else { return [] }
        var slots: [Slot] = []
        if bar.back != nil {
            slots.append(.back)
        }
        if bar.navigation != nil, !navigationShown {
            slots.append(.navigation)
        }
        return slots
    }

    /// Info beside Actions, Actions at the trailing-most end — the design
    /// canvas's `[ⓘ] [⋯]` ordering (2026-10-06 retire-the-context-bar design).
    static func trailingSlots(bar: PresentationContextBar?) -> [Slot] {
        guard let bar else { return [] }
        var slots: [Slot] = []
        if bar.info != nil {
            slots.append(.info)
        }
        if bar.secondary != nil {
            slots.append(.secondary)
        }
        return slots
    }
}

/// Where Core's `primary` slot goes: a full-width button at the bottom of
/// the surface's own content, never in the title row.
enum SurfacePrimaryButtonLayout {
    /// Whether the button scrolls with the surface's content. Never: it sits
    /// under the content area, so on a scrolling surface it stays in view
    /// instead of waiting at the end of the list, as on Android.
    static func scrollsWithContent(scrollsContent _: Bool) -> Bool {
        false
    }
}

/// Core's back/navigation/secondary/info slots (`SetContextBar`) drawn
/// inline in the surface's own title row, the way every platform already
/// puts them (HIG navigation bars) — replacing the row this shell used to
/// draw above the tab bar (2026-10-06 retire-the-context-bar design,
/// vauchi/private#479, #513, #532).
struct SurfaceTitleBarView: View {
    let surfaceID: String
    let title: String
    let bar: PresentationContextBar?
    let navigationShown: Bool
    let minimumTarget: CGFloat
    let onEvent: (PresentationEvent) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(
                SurfaceTitleBarLayout.leadingSlots(bar: bar, navigationShown: navigationShown),
                id: \.self
            ) { slot in
                leadingButton(slot)
            }
            Text(title)
                .font(.title2.bold())
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(SurfaceTitleBarLayout.trailingSlots(bar: bar), id: \.self) { slot in
                trailingButton(slot)
            }
        }
    }

    @ViewBuilder
    private func leadingButton(_ slot: SurfaceTitleBarLayout.Slot) -> some View {
        switch slot {
        case .back:
            if let back = bar?.back {
                backButton(back)
            }
        case .navigation:
            if let navigation = bar?.navigation {
                iconButton(navigation, systemImage: "line.3.horizontal", identifier: "command.navigation")
            }
        case .secondary, .info:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailingButton(_ slot: SurfaceTitleBarLayout.Slot) -> some View {
        switch slot {
        case .info:
            if let info = bar?.info {
                iconButton(info, systemImage: "info.circle", identifier: "command.info")
            }
        case .secondary:
            if let secondary = bar?.secondary {
                iconButton(secondary, systemImage: "ellipsis", identifier: "command.secondary")
            }
        case .back, .navigation:
            EmptyView()
        }
    }

    /// The platform's own chevron, plus Core's label when it sends one —
    /// the native back-button convention (iOS Human Interface Guidelines).
    private func backButton(_ action: PresentationAction) -> some View {
        Button {
            activate(action)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                if !action.label.isEmpty {
                    Text(action.label)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: minimumTarget)
        }
        .disabled(!action.enabled)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityIdentifier("command.back")
    }

    private func iconButton(
        _ action: PresentationAction,
        systemImage: String,
        identifier: String
    ) -> some View {
        Button {
            activate(action)
        } label: {
            Image(systemName: systemImage)
                .frame(width: minimumTarget, height: minimumTarget)
        }
        .disabled(!action.enabled)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityIdentifier(identifier)
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

/// Core's `primary` slot as a full-width button at the bottom of the
/// surface's own content (2026-10-06 retire-the-context-bar design).
struct SurfacePrimaryActionButtonView: View {
    let surfaceID: String
    let action: PresentationAction
    let minimumTarget: CGFloat
    let onEvent: (PresentationEvent) -> Void

    var body: some View {
        Button {
            onEvent(
                .actionActivated(surfaceID: surfaceID, interactionID: action.interactionID)
            )
        } label: {
            Text(action.label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(minHeight: minimumTarget)
        .disabled(!action.enabled)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityIdentifier("command.primary")
        .keyboardShortcut(
            action.shortcut == .undo ? "z" : .return,
            modifiers: .command
        )
    }
}
