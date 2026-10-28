// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// A theme picked in Core's Settings reaches the phone only as the surface's
// `tokens.colors` (Core 0.90.0, vauchi/private#814): the palette has to come
// from them, not from a theme store of the shell's own.

import SwiftUI
@testable import Vauchi
import XCTest

final class PresentationPaletteTests: XCTestCase {
    private func tokens(_ colors: String) throws -> PresentationTokens {
        let json = """
        {"spacing_small":4,"spacing_medium":8,"spacing_large":16,
         "corner_radius":8,"minimum_target_size":44,"colors":\(colors)}
        """
        return try JSONDecoder().decode(PresentationTokens.self, from: Data(json.utf8))
    }

    private let dracula = """
    {"background":"#282a36","surface":"#21222c","text":"#f8f8f2",
     "text_muted":"#bfbfbf","accent":"#bd93f9","border":"#6272a4",
     "success":"#50fa7b","warning":"#ffb86c","error":"#ff5555",
     "surface_input":"#191a21","surface_muted":null,"surface_elevated":null,
     "text_on_accent":null,"focus_ring":"#ff79c6"}
    """

    private func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    func testTheSurfacesColoursPaintEachRole() throws {
        let palette = try PresentationPalette(colors: tokens(dracula).colors)

        XCTAssertEqual(palette.background, rgb(0x28, 0x2A, 0x36))
        XCTAssertEqual(palette.surface, rgb(0x21, 0x22, 0x2C))
        XCTAssertEqual(palette.text, rgb(0xF8, 0xF8, 0xF2))
        XCTAssertEqual(palette.textMuted, rgb(0xBF, 0xBF, 0xBF))
        XCTAssertEqual(palette.accent, rgb(0xBD, 0x93, 0xF9))
        XCTAssertEqual(palette.border, rgb(0x62, 0x72, 0xA4))
        XCTAssertEqual(palette.success, rgb(0x50, 0xFA, 0x7B))
        XCTAssertEqual(palette.warning, rgb(0xFF, 0xB8, 0x6C))
        XCTAssertEqual(palette.error, rgb(0xFF, 0x55, 0x55))
        XCTAssertEqual(palette.surfaceInput, rgb(0x19, 0x1A, 0x21))
        XCTAssertEqual(palette.focusRing, rgb(0xFF, 0x79, 0xC6))
    }

    func testARoleTheThemeLeavesOutPaintsItsNearestRequiredRole() throws {
        let palette = try PresentationPalette(colors: tokens(dracula).colors)

        XCTAssertEqual(palette.surfaceMuted, palette.surface)
        XCTAssertEqual(palette.surfaceElevated, palette.surface)
        XCTAssertEqual(palette.textOnAccent, palette.background)

        let noRing = try PresentationPalette(
            colors: tokens(dracula.replacingOccurrences(of: "\"#ff79c6\"", with: "null")).colors
        )
        XCTAssertEqual(noRing.focusRing, noRing.accent)
    }

    func testASurfaceWithoutColoursPaintsTheSystemPalette() throws {
        let json = """
        {"spacing_small":4,"spacing_medium":8,"spacing_large":16,
         "corner_radius":8,"minimum_target_size":44}
        """
        let tokens = try JSONDecoder().decode(PresentationTokens.self, from: Data(json.utf8))

        XCTAssertNil(tokens.colors)
        XCTAssertEqual(PresentationPalette(colors: tokens.colors), .system)
    }

    func testOnlySixDigitHexIsAColour() {
        XCTAssertEqual(PresentationPalette.color(hex: "#bd93f9"), rgb(0xBD, 0x93, 0xF9))
        for bad in ["", "#", "bd93f9", "#bd93f", "#bd93f9ff", "#gg93f9", "#bd93f9 ", "#ｂd93f9"] {
            XCTAssertNil(PresentationPalette.color(hex: bad), bad)
        }
    }

    /// The status bar and native controls follow the window's style, so a
    /// dark theme on a light-mode phone drew a dark clock on a dark
    /// background (vauchi/private#814).
    /// @internal
    func testTheWindowTakesTheLightnessOfTheThemesBackground() throws {
        let latte = dracula.replacingOccurrences(of: "#282a36", with: "#eff1f5")

        XCTAssertEqual(try PresentationPalette(colors: tokens(dracula).colors).appearance, .dark)
        XCTAssertEqual(try PresentationPalette(colors: tokens(latte).colors).appearance, .light)
        XCTAssertNil(PresentationPalette(colors: nil).appearance)
        XCTAssertNil(
            try PresentationPalette(
                colors: tokens(dracula.replacingOccurrences(of: "#282a36", with: "red")).colors
            ).appearance
        )
    }

    func testADamagedRequiredRoleFallsBackToTheSystemColourForIt() throws {
        let palette = try PresentationPalette(
            colors: tokens(dracula.replacingOccurrences(of: "#282a36", with: "red")).colors
        )

        XCTAssertEqual(palette.background, PresentationPalette.system.background)
        XCTAssertEqual(palette.surface, rgb(0x21, 0x22, 0x2C))
    }
}
