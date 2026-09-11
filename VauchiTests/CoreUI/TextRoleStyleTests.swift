// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit
@testable import Vauchi
import XCTest

/// Guards the shell's obligation to honour every `PresentationTextStyle`
/// Core defines (`core/vauchi-core/src/platform/presentation/surface/nodes.rs`).
///
/// `textRoleStyle(for:)` is already exhaustive, so the compiler catches a
/// role that is never handled. It cannot catch a role handled *wrongly* —
/// changing `.monospace` to return `.body` compiles clean and silently
/// reverts monospaced text to proportional. Android shipped exactly that
/// bug. These tests are the part exhaustiveness cannot do.
final class TextRoleStyleTests: XCTestCase {
    private let allRoles: [PresentationTextStyle] = [
        .heading, .body, .caption, .monospace, .muted,
    ]

    private let bundledFontFiles = [
        "BricolageGrotesque[opsz,wdth,wght]",
        "HankenGrotesk[wght]",
        "HankenGrotesk-Italic[wght]",
        "JetBrainsMono[wght]",
        "JetBrainsMono-Italic[wght]",
    ]

    /// The unscaled size Apple's HIG defines for a text style, read from the
    /// system rather than hardcoded so this stays correct if HIG base sizes
    /// ever change. `Font.custom(_:size:relativeTo:)` treats `size` as this
    /// unscaled baseline and layers Dynamic Type scaling on top of it.
    private func defaultPointSize(for uiTextStyle: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(
            forTextStyle: uiTextStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
    }

    func testEveryRoleResolvesToADistinctPresentation() {
        let resolved = allRoles.map(textRoleStyle(for:))

        for (offset, style) in resolved.enumerated() {
            let duplicate = resolved.enumerated().first {
                $0.offset != offset && $0.element == style
            }
            XCTAssertNil(
                duplicate,
                "\(allRoles[offset]) collides with \(duplicate.map { allRoles[$0.offset] }.debugDescription); "
                    + "a collision means one role was folded into another"
            )
        }
    }

    func testHeadingUsesBricolageGrotesqueBold() {
        let size = defaultPointSize(for: .title2)

        XCTAssertEqual(
            textRoleStyle(for: .heading).font,
            .custom("BricolageGrotesque-96ptExtraBold_Bold", size: size, relativeTo: .title2)
        )
        XCTAssertFalse(textRoleStyle(for: .heading).muted)
    }

    func testBodyAndMutedUseHankenGroteskRegular() {
        let size = defaultPointSize(for: .body)
        let expectedFont = Font.custom("HankenGrotesk-Regular", size: size, relativeTo: .body)

        XCTAssertEqual(textRoleStyle(for: .body).font, expectedFont)
        XCTAssertEqual(textRoleStyle(for: .muted).font, expectedFont)
    }

    func testCaptionUsesHankenGroteskRegularAtCaptionSize() {
        let size = defaultPointSize(for: .caption1)

        XCTAssertEqual(
            textRoleStyle(for: .caption).font,
            .custom("HankenGrotesk-Regular", size: size, relativeTo: .caption)
        )
    }

    func testMonospaceUsesJetBrainsMonoRegular() {
        let size = defaultPointSize(for: .body)
        let style = textRoleStyle(for: .monospace)

        XCTAssertEqual(style.font, .custom("JetBrainsMono-Regular", size: size, relativeTo: .body))
        XCTAssertNotEqual(
            style.font, textRoleStyle(for: .body).font,
            "monospace must not fall back to the proportional Hanken Grotesk body font"
        )
        XCTAssertFalse(style.muted)
    }

    func testMutedReducesEmphasisWithoutChangingFont() {
        let muted = textRoleStyle(for: .muted)
        let body = textRoleStyle(for: .body)

        XCTAssertTrue(muted.muted, "muted must reduce emphasis")
        XCTAssertFalse(body.muted, "body must stay full emphasis")
        XCTAssertEqual(
            muted.font, body.font,
            "muted differs from body by emphasis, not by font"
        )
    }

    func testBundledFontResourcesArePresent() {
        for fileName in bundledFontFiles {
            XCTAssertNotNil(
                Bundle.main.url(forResource: fileName, withExtension: "ttf"),
                "\(fileName).ttf must ship in the app bundle for UIAppFonts to register it"
            )
        }
    }

    func testBrandFontFamiliesAreRegistered() {
        let familyNames = Set(UIFont.familyNames)

        for family in ["Bricolage Grotesque", "Hanken Grotesk", "JetBrains Mono"] {
            XCTAssertTrue(
                familyNames.contains(family),
                "\(family) must be registered via UIAppFonts for Font.custom to resolve it"
            )
        }
    }

    func testUnknownWireValueFallsBackToBody() throws {
        // A style this shell does not know (here "title", the retired
        // variant Core now projects as "heading") must not fail the whole
        // command batch: a Core-main screen catalog replayed through an
        // older shell renders it as body copy instead.
        let payload = Data(#""title""#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(PresentationTextStyle.self, from: payload),
            .body
        )
    }
}
