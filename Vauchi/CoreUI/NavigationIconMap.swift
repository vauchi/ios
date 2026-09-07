// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Resolves the platform-neutral `icon_token` Core attaches to a
/// `PresentationAction` into an SF Symbol name.
///
/// Core names its tokens after the SF Symbols core set, so most entries are
/// the identity mapping widened to the filled weight. The table stays
/// explicit anyway: handing an arbitrary Core token to `Image(systemName:)`
/// draws a blank gap the moment Core names a token this OS does not ship.
enum NavigationIconMap {
    /// Shown when Core sends a token this build does not know, so a new
    /// destination arrives with a marker instead of a hole in the row. An
    /// apps-grid glyph reads as "some section of this app" and stays
    /// truthful; reusing a concrete icon such as the house would put a
    /// confident lie next to a label that says something else.
    static let fallbackSymbol = "square.grid.2x2.fill"

    /// Filled weights throughout: outlines lose definition at the sizes a
    /// navigation row uses and are the first thing to disappear for low-vision
    /// users. Tokens whose symbol family ships no `.fill` (`qrcode`,
    /// `laptopcomputer`, `mappin.and.ellipse`) keep the base name.
    ///
    /// Every name here has to exist at this target's floor, not merely on the
    /// newest OS, or the icon silently vanishes for the oldest supported
    /// devices. `key.horizontal` is the one token that does not take its own
    /// family's fill for that reason: `key.horizontal.fill` arrived in iOS
    /// 16.1 and this app deploys to iOS 15, so it resolves to `key.fill`
    /// (iOS 14) — a filled key either way, and the same drive-not-cloud,
    /// key-not-lock reading the other shells use.
    private static let symbolsByToken: [String: String] = [
        "person.crop.rectangle": "person.crop.rectangle.fill",
        "person.2": "person.2.fill",
        "qrcode": "qrcode",
        "folder": "folder.fill",
        "tag": "tag.fill",
        "mappin.and.ellipse": "mappin.and.ellipse",
        "person.badge.plus": "person.fill.badge.plus",
        "gearshape": "gearshape.fill",
        "questionmark.circle": "questionmark.circle.fill",
        "key.horizontal": "key.fill",
        "laptopcomputer": "laptopcomputer",
        // A drive, not a cloud: backup here is guardian-held and local, and a
        // cloud glyph would describe a threat model this product rejects.
        "externaldrive": "externaldrive.fill",
        "hand.raised": "hand.raised.fill",
        "bubble.left.and.bubble.right": "bubble.left.and.bubble.right.fill",
        "list.bullet.rectangle": "list.bullet.rectangle.fill",
        "house": "house.fill",
    ]

    /// Total over every token, present or not.
    static func systemImage(for token: String?) -> String {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            return fallbackSymbol
        }
        return symbolsByToken[token] ?? fallbackSymbol
    }

    /// The navigation overlay is this shell's menu of destinations, so every
    /// row there gets an icon beside its label even when Core sent no token.
    /// Other overlays only show one where Core actually named an icon, so an
    /// action menu does not sprout a column of meaningless markers.
    static func systemImage(
        forOverlayKind kind: PresentationOverlayKind,
        token: String?
    ) -> String? {
        guard kind == .navigation || token != nil else { return nil }
        return systemImage(for: token)
    }
}
