// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
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

    func testMonospaceResolvesToAMonospacedFace() {
        let style = textRoleStyle(for: .monospace)

        XCTAssertEqual(style.font, .system(.body, design: .monospaced))
        XCTAssertNotEqual(
            style.font, .body,
            "monospace must not fall back to the proportional body font"
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

    func testHeadingAndCaptionDifferFromBody() {
        XCTAssertEqual(textRoleStyle(for: .heading).font, .title2.bold())
        XCTAssertEqual(textRoleStyle(for: .caption).font, .caption)
        XCTAssertEqual(textRoleStyle(for: .body).font, .body)
    }

    func testUnknownWireValueIsRejectedOnDecode() {
        // The role enum is String-backed and carries no `unknown` case, so
        // Swift's synthesized decoder fails closed. "title" is the retired
        // variant Core now projects as "heading".
        let payload = Data(#""title""#.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode(PresentationTextStyle.self, from: payload)
        )
    }
}
