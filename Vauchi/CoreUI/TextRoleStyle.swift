// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// How a `PresentationTextStyle` role is presented natively.
///
/// Font and emphasis travel together because they are not independent:
/// `.muted` shares `.body`'s font and differs only in foreground, so
/// neither value identifies a role on its own.
struct TextRoleStyle: Equatable {
    let font: Font
    let muted: Bool
}

/// Resolve Core's semantic text role to native SwiftUI styling.
///
/// Core sends a role rather than a size so the shell can pick a native
/// text style and inherit Dynamic Type (ADR-021, ADR-066).
///
/// Deliberately has no `default` branch: a role added to Core must break
/// this build rather than fall back silently. Note that exhaustiveness
/// alone is not sufficient — it proves a role was handled, never that it
/// resolved correctly — which is what `TextRoleStyleTests` covers.
func textRoleStyle(for style: PresentationTextStyle) -> TextRoleStyle {
    switch style {
    case .heading: TextRoleStyle(font: .title2.bold(), muted: false)
    case .body: TextRoleStyle(font: .body, muted: false)
    case .caption: TextRoleStyle(font: .caption, muted: false)
    case .monospace: TextRoleStyle(font: .system(.body, design: .monospaced), muted: false)
    case .muted: TextRoleStyle(font: .body, muted: true)
    }
}
