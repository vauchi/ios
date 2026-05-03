// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// LockScreenView.swift
// Branded lock screen shown when device authentication is required
// Based on: _private/docs/problems/2026-03-02-locked-device-startup-error/

import SwiftUI

/// Branded lock screen displayed when the device is locked and authentication
/// is required to access the Keychain. Follows the Bitwarden/1Password pattern:
/// shows app branding with a "Tap to Unlock" button that triggers system auth
/// (Face ID / Touch ID / passcode).
struct LockScreenView: View {
    let onUnlock: () -> Void

    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.cyan)
                .accessibilityHidden(true)

            Text(localizationService.t("lock.title"))
                .font(Font.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Text(localizationService.t("lock.subtitle"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onUnlock) {
                Label(
                    localizationService.t("lock.unlock_button"),
                    systemImage: "lock.open.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.horizontal, 48)
            .accessibilityHint(localizationService.t("lock.a11y_hint"))

            Spacer()
        }
        .padding()
        .onAppear {
            // Auto-trigger authentication on first appearance
            onUnlock()
        }
    }
}

#Preview("Lock Screen") {
    LockScreenView(onUnlock: {})
}
