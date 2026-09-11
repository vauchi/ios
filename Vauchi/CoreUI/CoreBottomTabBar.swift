// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Pure layout and accessibility decisions for `CoreBottomTabBar`, kept out
/// of the view so `CoreBottomTabBarLayoutTests` can assert them without
/// rendering.
enum CoreBottomTabBarLayout {
    /// Exchange is the raised centre action among Core's navigation
    /// destinations (Option A, 2026-09-07 familiar-simple-interface
    /// review) — the app's purpose, not a peer of the other four. Keyed on
    /// the icon token Core already sends, the same vocabulary
    /// `NavigationIconMap` resolves, so the shell reacts to presentation
    /// vocabulary rather than inventing a domain rule about "Exchange".
    static func isCentreAction(tab: PresentationNavigationItem) -> Bool {
        tab.iconToken == "qrcode"
    }

    /// VoiceOver's own "tab N of M" convention, one-indexed like the
    /// platform's native tab bar — nobody hears "tab 0".
    static func accessibilityValue(position: Int, of count: Int) -> String {
        "tab \(position + 1) of \(count)"
    }

    /// Core reports which destination is current directly on each item
    /// (`SetNavigation`), so the shell reflects it rather than deriving it
    /// from any local state.
    static func isSelected(tab: PresentationNavigationItem) -> Bool {
        tab.selected
    }

    /// An empty `items` list means the surface offers no destinations (a
    /// locked app) — Core's contract for `NavigationSpec`, mirrored so the
    /// bar hides instead of rendering with nothing in it.
    static func isVisible(items: [PresentationNavigationItem]) -> Bool {
        !items.isEmpty
    }
}

/// Renders Core's persistent navigation surface (`SetNavigation`) as the
/// native bottom-tab-bar idiom Option A asks for, and the fix for
/// `2026-06-02-ios-custom-tabbar-accessibility`: a plain row of buttons
/// reads to VoiceOver as ungrouped generic buttons, not as a tab bar. The
/// `navigation`-kind overlay keeps its own panel (`PresentationOverlayView`);
/// stacking a second bar over this one hid the command bar behind it.
struct CoreBottomTabBar: View {
    let surfaceID: String
    let items: [PresentationNavigationItem]
    let onEvent: (PresentationEvent) -> Void

    private static let centreDiameter: CGFloat = 64

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, tab in
                tabButton(tab, position: index)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigationDestinations")
        .tabBarTrait()
    }

    private func tabButton(_ tab: PresentationNavigationItem, position: Int) -> some View {
        Button {
            onEvent(.actionActivated(surfaceID: surfaceID, interactionID: tab.interactionID))
        } label: {
            if CoreBottomTabBarLayout.isCentreAction(tab: tab) {
                centreLabel(tab)
            } else {
                sideLabel(tab)
            }
        }
        .frame(maxWidth: .infinity)
        // One VoiceOver stop per destination. Modifying the button's own
        // label is not enough: SwiftUI lifts the `Image` out of the button's
        // subtree and publishes it as a sibling button named after the SF
        // Symbol ("person.crop.rectangle.fill"), so every destination read
        // twice. Only replacing the subtree with one synthetic button
        // collapses it, the same way `PresentationOverlayView` does.
        .accessibilityRepresentation {
            Button(tab.accessibilityLabel) {}
                .accessibilityValue(
                    CoreBottomTabBarLayout.accessibilityValue(position: position, of: items.count)
                )
                .accessibilityAddTraits(CoreBottomTabBarLayout.isSelected(tab: tab) ? .isSelected : [])
        }
    }

    private func centreLabel(_ tab: PresentationNavigationItem) -> some View {
        VStack(spacing: 4) {
            icon(tab, font: .title2)
                .foregroundColor(.white)
                .frame(width: Self.centreDiameter, height: Self.centreDiameter)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .offset(y: -Self.centreDiameter / 4)
            Text(tab.label)
                .font(.caption2)
                .offset(y: -Self.centreDiameter / 4)
        }
    }

    private func sideLabel(_ tab: PresentationNavigationItem) -> some View {
        VStack(spacing: 2) {
            icon(tab, font: .title3)
            Text(tab.label)
                .font(.caption2)
        }
        .padding(.vertical, 6)
        .foregroundColor(tab.selected ? .accentColor : .primary)
    }

    private func icon(_ tab: PresentationNavigationItem, font: Font) -> some View {
        Image(systemName: NavigationIconMap.systemImage(for: tab.iconToken))
            .font(font)
            .overlay(alignment: .topTrailing) {
                if tab.badgeCount > 0 {
                    TabBarBadge(count: tab.badgeCount)
                        .offset(x: 10, y: -8)
                }
            }
    }
}

private struct TabBarBadge: View {
    let count: UInt32

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.red, in: Capsule())
            .accessibilityHidden(true)
    }
}

private extension View {
    /// `.isTabBar` arrived in iOS 17; this app's floor is 15
    /// (`NavigationIconMap`'s `key.horizontal` comment explains why), so the
    /// container falls back to the plain `.contain` grouping already applied
    /// on older runtimes rather than failing to build.
    @ViewBuilder
    func tabBarTrait() -> some View {
        if #available(iOS 17.0, *) {
            accessibilityAddTraits(.isTabBar)
        } else {
            self
        }
    }
}
