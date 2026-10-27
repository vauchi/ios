// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit

/// The colours a surface paints with, from its `tokens.colors` (Core
/// 0.90.0, vauchi/private#814).
struct PresentationPalette: Equatable {
    let background: Color
    let surface: Color
    let surfaceInput: Color
    let surfaceMuted: Color
    let surfaceElevated: Color
    let text: Color
    let textMuted: Color
    let textOnAccent: Color
    let accent: Color
    let border: Color
    let focusRing: Color
    let success: Color
    let warning: Color
    let error: Color

    static let system = PresentationPalette(
        background: Color(uiColor: .systemBackground),
        surface: Color(uiColor: .secondarySystemBackground),
        surfaceInput: Color(uiColor: .tertiarySystemBackground),
        surfaceMuted: Color(uiColor: .secondarySystemBackground),
        surfaceElevated: Color(uiColor: .secondarySystemBackground),
        text: Color(uiColor: .label),
        textMuted: Color(uiColor: .secondaryLabel),
        textOnAccent: .white,
        accent: .accentColor,
        border: Color(uiColor: .separator),
        focusRing: .accentColor,
        success: Color(uiColor: .systemGreen),
        warning: Color(uiColor: .systemOrange),
        error: Color(uiColor: .systemRed)
    )
}

extension PresentationPalette {
    /// A role the theme leaves out paints as its nearest required role; a
    /// damaged required role, or a surface from a Core without colours,
    /// paints the system's.
    init(colors: PresentationColors?) {
        let system = Self.system
        guard let colors else {
            self = system
            return
        }
        func paint(_ hex: String?, else fallback: Color) -> Color {
            hex.flatMap(Self.color(hex:)) ?? fallback
        }
        let background = paint(colors.background, else: system.background)
        let surface = paint(colors.surface, else: system.surface)
        let accent = paint(colors.accent, else: system.accent)
        self.init(
            background: background,
            surface: surface,
            surfaceInput: paint(colors.surfaceInput, else: surface),
            surfaceMuted: paint(colors.surfaceMuted, else: surface),
            surfaceElevated: paint(colors.surfaceElevated, else: surface),
            text: paint(colors.text, else: system.text),
            textMuted: paint(colors.textMuted, else: system.textMuted),
            textOnAccent: paint(colors.textOnAccent, else: background),
            accent: accent,
            border: paint(colors.border, else: system.border),
            focusRing: paint(colors.focusRing, else: accent),
            success: paint(colors.success, else: system.success),
            warning: paint(colors.warning, else: system.warning),
            error: paint(colors.error, else: system.error)
        )
    }

    /// `#rrggbb`, the only form Core sends.
    static func color(hex: String) -> Color? {
        let digits = hex.utf8.dropFirst()
        guard hex.utf8.first == UInt8(ascii: "#"), digits.count == 6,
              digits.allSatisfy({ isHexDigit($0) }),
              let text = String(bytes: digits, encoding: .utf8),
              let value = UInt32(text, radix: 16)
        else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"),
             UInt8(ascii: "a") ... UInt8(ascii: "f"),
             UInt8(ascii: "A") ... UInt8(ascii: "F"):
            true
        default:
            false
        }
    }
}

private struct PresentationPaletteKey: EnvironmentKey {
    static let defaultValue = PresentationPalette.system
}

extension EnvironmentValues {
    var presentationPalette: PresentationPalette {
        get { self[PresentationPaletteKey.self] }
        set { self[PresentationPaletteKey.self] = newValue }
    }
}
