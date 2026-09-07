// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
@testable import Vauchi
import XCTest

/// Pins the shell's obligation to draw a distinct, legible glyph for every
/// navigation destination Core names.
///
/// Core tags each destination with a platform-neutral `icon_token`
/// (`tab_metadata` in `core/vauchi-app/src/ui/app_engine/navigation.rs`) and
/// ships it as `ActionSpec.icon_token`
/// (`core/vauchi-app/src/ui/contextual_surface.rs`). The token is a *name*,
/// not an asset, so each shell owns its own resolution table.
///
/// Totality on its own is not the property that matters here: a table with an
/// entry for all sixteen tokens still proves only that each was *handled*.
/// Sixteen identical glyphs above sixteen labels satisfies "every token has an
/// icon" and is the exact bug this map exists to fix, which is why the
/// per-token expectation and the distinctness test are both present.
final class NavigationIconMapTests: XCTestCase {
    /// Every token `tab_metadata` can emit — including `house`, the value it
    /// resolves unlisted screens to — paired with the symbol this shell owes
    /// it. Kept as the full table rather than the five destinations the menu
    /// shows today, so a screen becoming reachable cannot arrive unglyphed.
    private static let expectedSymbolsByToken: [(token: String, symbol: String)] = [
        ("person.crop.rectangle", "person.crop.rectangle.fill"),
        ("person.2", "person.2.fill"),
        ("qrcode", "qrcode"),
        ("folder", "folder.fill"),
        ("tag", "tag.fill"),
        ("mappin.and.ellipse", "mappin.and.ellipse"),
        ("person.badge.plus", "person.fill.badge.plus"),
        ("gearshape", "gearshape.fill"),
        ("questionmark.circle", "questionmark.circle.fill"),
        ("key.horizontal", "key.fill"),
        ("laptopcomputer", "laptopcomputer"),
        ("externaldrive", "externaldrive.fill"),
        ("hand.raised", "hand.raised.fill"),
        ("bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill"),
        ("list.bullet.rectangle", "list.bullet.rectangle.fill"),
        ("house", "house.fill"),
    ]

    private func symbolExists(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }

    func testEveryCoreNavigationTokenResolvesToItsSymbol() {
        for (token, expected) in Self.expectedSymbolsByToken {
            XCTAssertEqual(
                NavigationIconMap.systemImage(for: token),
                expected,
                "token '\(token)' resolved to the wrong symbol"
            )
        }
    }

    /// The point of the icons is that a destination is recognisable before its
    /// label is read, which two destinations sharing a glyph destroys.
    func testEveryDestinationGetsADistinctSymbol() {
        var tokensBySymbol: [String: [String]] = [:]
        for (token, _) in Self.expectedSymbolsByToken {
            tokensBySymbol[NavigationIconMap.systemImage(for: token), default: []]
                .append(token)
        }

        let shared = tokensBySymbol.filter { $0.value.count > 1 }
        XCTAssertTrue(
            shared.isEmpty,
            "destinations sharing one glyph are indistinguishable: \(shared)"
        )
    }

    /// A name this OS cannot resolve renders as a blank gap beside the label,
    /// so every mapped name has to be a symbol the system actually ships.
    func testEveryMappedSymbolIsInstalled() {
        for (token, _) in Self.expectedSymbolsByToken {
            let symbol = NavigationIconMap.systemImage(for: token)
            XCTAssertTrue(
                symbolExists(symbol),
                "token '\(token)' mapped to unknown SF Symbol '\(symbol)'"
            )
        }
    }

    /// Outlines lose definition at the sizes a navigation row uses and are the
    /// first thing to disappear for low-vision users, so the table takes the
    /// filled weight wherever the symbol family offers one. Phrased as "no
    /// fuller variant remains" so a family that gains a fill in a later OS is
    /// caught rather than silently left thin.
    func testMappedSymbolsPreferFilledVariants() {
        for (token, _) in Self.expectedSymbolsByToken {
            let symbol = NavigationIconMap.systemImage(for: token)
            XCTAssertFalse(
                symbolExists(symbol + ".fill"),
                "token '\(token)' mapped to '\(symbol)' but '\(symbol).fill' exists"
            )
        }
    }

    /// Backup here is guardian-held and local. A cloud glyph would describe a
    /// threat model this product does not have.
    func testBackupResolvesToADriveNotACloud() {
        let symbol = NavigationIconMap.systemImage(for: "externaldrive")

        XCTAssertEqual(symbol, "externaldrive.fill")
        XCTAssertFalse(
            symbol.contains("cloud"),
            "backup is guardian-held and local; a cloud glyph misstates that"
        )
    }

    /// Core can add a screen before this shell learns its token, so an
    /// unmapped token must still put something truthful beside the label.
    func testUnknownTokenFallsBackToTheNeutralSymbol() {
        XCTAssertEqual(
            NavigationIconMap.systemImage(for: "sparkles.rectangle.not.a.symbol"),
            NavigationIconMap.fallbackSymbol
        )
    }

    /// `icon_token` is optional in the presentation protocol.
    func testMissingOrBlankTokenFallsBackToTheNeutralSymbol() {
        XCTAssertEqual(
            NavigationIconMap.systemImage(for: nil),
            NavigationIconMap.fallbackSymbol
        )
        XCTAssertEqual(
            NavigationIconMap.systemImage(for: ""),
            NavigationIconMap.fallbackSymbol
        )
        XCTAssertEqual(
            NavigationIconMap.systemImage(for: "   "),
            NavigationIconMap.fallbackSymbol
        )
    }

    /// The fallback has to be installed, filled like the rest of the table,
    /// and — the part that matters — must not borrow a destination's meaning.
    /// A house beside a label reading "Wallet" is a more confident lie than an
    /// unclaimed grid.
    func testFallbackIsAnInstalledFilledSymbolThatClaimsNoDestination() {
        let fallback = NavigationIconMap.fallbackSymbol

        XCTAssertTrue(symbolExists(fallback))
        XCTAssertFalse(symbolExists(fallback + ".fill"))
        XCTAssertNotEqual(fallback, NavigationIconMap.systemImage(for: "house"))

        let claimed = Self.expectedSymbolsByToken.map {
            NavigationIconMap.systemImage(for: $0.token)
        }
        XCTAssertFalse(
            claimed.contains(fallback),
            "the unknown-token glyph must not be a destination's own glyph"
        )
    }

    /// Whatever arrives on the wire resolves to something drawable.
    func testResolutionIsTotalOverAdversarialTokens() {
        let hostile = [
            "", " ", "\u{0}", "HOUSE", "house.fill", "../../etc/passwd",
            "🔑", String(repeating: "a", count: 4096),
        ]

        for token in hostile {
            XCTAssertTrue(
                symbolExists(NavigationIconMap.systemImage(for: token)),
                "token '\(token.prefix(32))' resolved to a name the system cannot draw"
            )
        }
    }

    /// The navigation overlay is this shell's menu of destinations, so every
    /// row there carries a glyph even when Core sent no token. An action menu
    /// only shows one where Core actually named an icon, so it does not sprout
    /// a column of meaningless markers.
    func testNavigationIconsEveryItemWhileActionMenuIconsOnlyTokenedOnes() {
        XCTAssertEqual(
            NavigationIconMap.systemImage(forOverlayKind: .navigation, token: nil),
            NavigationIconMap.fallbackSymbol
        )
        XCTAssertNil(
            NavigationIconMap.systemImage(forOverlayKind: .actionMenu, token: nil)
        )
        XCTAssertEqual(
            NavigationIconMap.systemImage(forOverlayKind: .actionMenu, token: "house"),
            "house.fill"
        )
    }
}
