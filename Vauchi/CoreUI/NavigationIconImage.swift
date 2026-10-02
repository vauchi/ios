// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Draws a resolved `NavigationIcon` so a bundled pictogram sits where an
/// SF Symbol would: tinted by the foreground style and sized with Dynamic
/// Type. A symbol follows the surrounding `.font`; an asset image does not,
/// so it gets a point size scaled relative to the text style it stands in for.
struct NavigationIconImage: View {
    private let icon: NavigationIcon
    @ScaledMetric private var side: CGFloat

    init(
        _ icon: NavigationIcon,
        pointSize: CGFloat = 20,
        relativeTo textStyle: Font.TextStyle = .body
    ) {
        self.icon = icon
        _side = ScaledMetric(wrappedValue: pointSize, relativeTo: textStyle)
    }

    var body: some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
        case let .asset(name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        }
    }
}
