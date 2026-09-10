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
    static func isCentreAction(tab: PresentationAction) -> Bool {
        tab.iconToken == "qrcode"
    }

    /// VoiceOver's own "tab N of M" convention, one-indexed like the
    /// platform's native tab bar — nobody hears "tab 0".
    static func accessibilityValue(position: Int, of count: Int) -> String {
        "tab \(position + 1) of \(count)"
    }

    static func isSelected(tab: PresentationAction, selectedInteractionID: String?) -> Bool {
        selectedInteractionID != nil && tab.interactionID == selectedInteractionID
    }
}

/// Renders Core's `navigation`-kind overlay as persistent-looking bottom
/// chrome instead of `PresentationOverlayView`'s full-screen sheet — the
/// native bottom-tab-bar idiom Option A asks for, and the fix for
/// `2026-06-02-ios-custom-tabbar-accessibility`: a plain row of buttons
/// reads to VoiceOver as ungrouped generic buttons, not as a tab bar.
///
/// `selectedInteractionID` exists for forward compatibility. Core does not
/// yet report which destination is current — the overlay's items carry no
/// such flag, and deriving it from the active surface would be the shell
/// interpreting domain state ADR-066 reserves to Core — so every call site
/// today passes `nil` and `.isSelected` stays inert until Core adds it.
struct CoreBottomTabBar: View {
    let surfaceID: String
    let items: [PresentationAction]
    let selectedInteractionID: String?
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

    private func tabButton(_ tab: PresentationAction, position: Int) -> some View {
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
        .disabled(!tab.enabled)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityValue(
            CoreBottomTabBarLayout.accessibilityValue(position: position, of: items.count)
        )
        .accessibilityAddTraits(
            CoreBottomTabBarLayout.isSelected(
                tab: tab,
                selectedInteractionID: selectedInteractionID
            ) ? .isSelected : []
        )
    }

    private func centreLabel(_ tab: PresentationAction) -> some View {
        VStack(spacing: 4) {
            Image(systemName: NavigationIconMap.systemImage(for: tab.iconToken))
                .font(.title2)
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

    private func sideLabel(_ tab: PresentationAction) -> some View {
        VStack(spacing: 2) {
            Image(systemName: NavigationIconMap.systemImage(for: tab.iconToken))
                .font(.title3)
            Text(tab.label)
                .font(.caption2)
        }
        .padding(.vertical, 6)
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
