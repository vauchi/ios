// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

extension PresentationTokens {
    /// Apple's own touch-target floor (P5, 2026-09-07 cross-frontend
    /// review), used only for chrome asked to render before any surface has
    /// supplied a token — every surface Core emits carries one.
    static let fallbackMinimumTargetSize: CGFloat = 48

    static func minimumTargetSize(from tokens: PresentationTokens?) -> CGFloat {
        tokens.map { CGFloat($0.minimumTargetSize) } ?? fallbackMinimumTargetSize
    }
}
