// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// WaitingForUnlockView.swift
// Passive waiting screen shown when protected data is unavailable
// Based on: _private/docs/problems/2026-03-02-locked-device-startup-error/

import SwiftUI

/// Passive waiting screen displayed when the device's protected data is
/// unavailable (e.g., iOS 15+ prewarming launches the app before first unlock).
/// The app automatically retries initialization when the device is unlocked
/// via `protectedDataDidBecomeAvailableNotification`.
struct WaitingForUnlockView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("Waiting for device unlock")
                .font(.title3)
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)

            Text("Vauchi will load automatically once your device is unlocked.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vauchi is waiting for device unlock. The app will load automatically once your device is unlocked.")
    }
}

#Preview("Waiting for Unlock") {
    WaitingForUnlockView()
}
