// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Resolves the platform-neutral `icon_token` Core attaches to a
/// `PresentationAction` or a `Status` node into an SF Symbol name.
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
        // Tokens Core puts on `Status` rows (`icon_token` across
        // `core/vauchi-app/src`). The glyph leads the row's title, so on
        // the lock screen it is the whole message; every token Core emits
        // there has a mapping so none falls back to the placeholder.
        "lock": "lock.fill",
        "warning": "exclamationmark.triangle.fill",
        "exclamationmark.triangle": "exclamationmark.triangle.fill",
        "info": "info.circle.fill",
        "checkmark.seal": "checkmark.seal.fill",
        "checkmark.shield": "checkmark.shield.fill",
        "exclamationmark.shield": "exclamationmark.shield.fill",
        "shield": "shield.fill",
        "checkmark.circle": "checkmark.circle.fill",
        "checkmark.circle.fill": "checkmark.circle.fill",
        "checkmark": "checkmark",
        "xmark": "xmark",
        "xmark.circle": "xmark.circle.fill",
        "delete": "trash.fill",
        "trash": "trash.fill",
        "devices": "laptopcomputer.and.iphone",
        "eye": "eye.fill",
        "key": "key.fill",
        "people": "person.2.fill",
        "person": "person.fill",
        "swap": "arrow.left.arrow.right",
        "arrow.left.arrow.right": "arrow.left.arrow.right",
        "link": "link",
        "lifebuoy": "lifepreserver.fill",
        "heart": "heart.fill",
        // Brand marks are not SF Symbols: a donation reads as a heart and
        // a code host as code, rather than a placeholder grid.
        "liberapay": "heart.fill",
        "github": "chevron.left.forwardslash.chevron.right",
        "wifi": "wifi",
        "cloud": "cloud.fill",
        "clock": "clock.fill",
        "clock.arrow.circlepath": "clock.arrow.circlepath",
        "camera": "camera.fill",
        // `camera.slash` lands on the same glyph because the slashed
        // family has no filled weight at this target's iOS 15 floor.
        "camera.slash": "camera.fill",
        "photo": "photo.fill",
        "qr": "qrcode",
        "drive": "externaldrive.fill",
        "more": "ellipsis",
        "id_card": "person.text.rectangle.fill",
        "sparkles": "sparkles",
        "sun.max": "sun.max.fill",
        "sun.min": "sun.min.fill",
        "textformat": "textformat",
        "dot.radiowaves.left.and.right": "dot.radiowaves.left.and.right",
        "move.3d": "move.3d",
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
