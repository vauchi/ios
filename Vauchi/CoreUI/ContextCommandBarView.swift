// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Where Core's four context-bar slots go, kept out of the view so
/// `ContextCommandBarLayoutTests` can assert it without rendering.
enum ContextCommandBarLayout {
    enum Slot: Equatable {
        case back
        case navigation
        case primary
        case secondary
    }

    static let restingClearance: CGFloat = 4

    /// Air between the row and a raised centre action: at 4 the primary
    /// button and the circle read as touching in the catalogue render.
    static let centreActionGap: CGFloat = 12

    /// The slots Core filled, in drawing order. An absent action takes no
    /// space: a held-open gap pushed the whole row off-centre.
    static func slots(bar: PresentationContextBar?) -> [Slot] {
        guard let bar else { return [] }
        var slots: [Slot] = []
        if bar.back != nil {
            slots.append(.back)
        }
        if bar.navigation != nil {
            slots.append(.navigation)
        }
        if bar.primary != nil {
            slots.append(.primary)
        }
        if bar.secondary != nil {
            slots.append(.secondary)
        }
        return slots
    }

    /// The launchers open a menu, and their icons alone were not understood
    /// (vauchi/private#479); the back chevron is the platform's own.
    static func showsLabel(_ slot: Slot) -> Bool {
        slot == .navigation || slot == .secondary
    }

    /// The primary button fills the row; without one a gap takes its place
    /// so Back stays leading and the launchers trailing.
    static func needsFlexibleGap(slots: [Slot]) -> Bool {
        !slots.contains(.primary)
    }

    static func bottomClearance(above tabs: [PresentationNavigationItem]) -> CGFloat {
        if tabs.contains(where: CoreBottomTabBarLayout.isCentreAction(tab:)) {
            return CoreBottomTabBarLayout.centreOverhang + centreActionGap
        }
        return restingClearance
    }
}

/// Core's context bar as one row on the same material as the tab bar below
/// it, so the two read as a single bottom area rather than a card stacked
/// on a bar.
struct ContextCommandBarView: View {
    let surfaceID: String
    let bar: PresentationContextBar?
    let windowClass: PresentationWindowClass
    let minimumTarget: CGFloat
    let bottomClearance: CGFloat
    let onEvent: (PresentationEvent) -> Void

    /// The launcher labels match the tab bar's caption size at the default
    /// text size. `.caption2` itself stays at 11 points from the smallest
    /// setting up to the default one, so it does not follow the text size
    /// there; scaled against `.subheadline` the label changes at every step.
    @ScaledMetric(relativeTo: .subheadline) private var launcherLabelSize: CGFloat = 11

    var body: some View {
        let slots = ContextCommandBarLayout.slots(bar: bar)
        if !slots.isEmpty {
            HStack(spacing: 8) {
                if let back = bar?.back {
                    roleButton(back, slot: .back, systemImage: "chevron.left", identifier: "command.back")
                }
                if let navigation = bar?.navigation {
                    roleButton(
                        navigation,
                        slot: .navigation,
                        systemImage: "line.3.horizontal",
                        identifier: "command.navigation"
                    )
                }
                if let primary = bar?.primary {
                    primaryButton(primary)
                }
                if ContextCommandBarLayout.needsFlexibleGap(slots: slots) {
                    Spacer(minLength: 0)
                }
                if let secondary = bar?.secondary {
                    roleButton(
                        secondary,
                        slot: .secondary,
                        systemImage: "ellipsis",
                        identifier: "command.secondary"
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, bottomClearance)
            .frame(maxWidth: windowClass == .compact ? .infinity : 620)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Contextual commands")
        }
    }

    private func primaryButton(_ primary: PresentationAction) -> some View {
        Button {
            activate(primary)
        } label: {
            Text(primary.label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(minHeight: minimumTarget)
        .disabled(!primary.enabled)
        .accessibilityLabel(primary.accessibilityLabel)
        .accessibilityIdentifier("command.primary")
        .keyboardShortcut(
            primary.shortcut == .undo ? "z" : .return,
            modifiers: .command
        )
    }

    private func roleButton(
        _ action: PresentationAction,
        slot: ContextCommandBarLayout.Slot,
        systemImage: String,
        identifier: String
    ) -> some View {
        Button {
            activate(action)
        } label: {
            if ContextCommandBarLayout.showsLabel(slot) {
                VStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(action.label)
                        .font(.system(size: launcherLabelSize))
                }
                .fixedSize()
                .frame(minWidth: minimumTarget, minHeight: minimumTarget)
            } else {
                Image(systemName: systemImage)
                    .frame(width: minimumTarget, height: minimumTarget)
            }
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
