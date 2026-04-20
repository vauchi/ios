// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Passcode policy shared between the unified app-password entry surface
/// (`AppPasswordView`) and the setup dialogs in
/// `ResistanceSettingsViews`. Min 4 lets users choose a numeric PIN; max
/// 64 leaves room for full passwords. Accepts any character set — the
/// underlying secret is a password, not a numeric PIN.
///
/// TODO(G3): replace the local bounds with
/// `VauchiPlatform.passcodeMinLength()` / `passcodeMaxLength()` once the
/// bindings ship 0.20.3. See
/// `_private/docs/problems/2026-04-16-frontend-pure-renderer-violations`
/// Phase 1 G3.
enum PasscodePolicy {
    static let minLength = 4
    static let maxLength = 64

    static func isValid(_ passcode: String) -> Bool {
        (minLength ... maxLength).contains(passcode.count)
    }

    static func clamp(_ input: String) -> String {
        String(input.prefix(maxLength))
    }
}
