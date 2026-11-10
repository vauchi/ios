// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The exchange ceremony's one beat: a check mark that scales in over the
/// screen and fades (`Command::Celebrate`, animation `cards_meet`).
/// Decorative only, so it is hidden from assistive technology; the haptic
/// and Core's milestone toast are what VoiceOver gets.
struct CelebrationFlashView: View {
    let visible: Bool

    var body: some View {
        ZStack {
            if visible {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Color(.systemBackground)) // design-token-ok: the mark on the accent disc, system role
                }
                .frame(width: 96, height: 96)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityIdentifier("celebration_flash")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.24), value: visible)
    }
}
