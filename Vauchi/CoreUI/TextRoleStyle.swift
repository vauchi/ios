// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit

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
    case .heading:
        TextRoleStyle(font: brandFont(named: headingFace, matching: .title2, relativeTo: .title2), muted: false)
    case .body:
        TextRoleStyle(font: brandFont(named: bodyFace, matching: .body, relativeTo: .body), muted: false)
    case .caption:
        TextRoleStyle(font: brandFont(named: bodyFace, matching: .caption1, relativeTo: .caption), muted: false)
    case .monospace:
        TextRoleStyle(font: brandFont(named: monospaceFace, matching: .body, relativeTo: .body), muted: false)
    case .muted:
        TextRoleStyle(font: brandFont(named: bodyFace, matching: .body, relativeTo: .body), muted: true)
    }
}

/// Bricolage Grotesque's default (non-instanced) master sits at ExtraBold,
/// so its named instances register on iOS under that master's PostScript
/// name rather than under the family's Regular weight — the Bold (700)
/// instance used for `.heading` is `BricolageGrotesque-96ptExtraBold_Bold`,
/// confirmed against `UIFont.fontNames(forFamilyName:)` at registration.
private let headingFace = "BricolageGrotesque-96ptExtraBold_Bold"
private let bodyFace = "HankenGrotesk-Regular"
private let monospaceFace = "JetBrainsMono-Regular"

/// `Font.custom(_:size:relativeTo:)` needs an unscaled base size; reading
/// it from `UIFont.preferredFont` at the `.large` (default) content size
/// category avoids hardcoding HIG point values that Apple could change.
private func brandFont(
    named postScriptName: String,
    matching uiTextStyle: UIFont.TextStyle,
    relativeTo textStyle: Font.TextStyle
) -> Font {
    let baseSize = UIFont.preferredFont(
        forTextStyle: uiTextStyle,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
    ).pointSize
    return .custom(postScriptName, size: baseSize, relativeTo: textStyle)
}
