// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import VauchiPlatform

/// Passcode policy shared between the unified app-password entry surface
/// (`AppPasswordView`) and the setup dialogs in
/// `ResistanceSettingsViews`. Bounds are resolved from core via
/// `passcodeMinLength()` / `passcodeMaxLength()` so the policy stays in
/// sync with Android and any future frontend.
enum PasscodePolicy {
    static let minLength = Int(passcodeMinLength())
    static let maxLength = Int(passcodeMaxLength())

    static func isValid(_ passcode: String) -> Bool {
        (minLength ... maxLength).contains(passcode.count)
    }

    static func clamp(_ input: String) -> String {
        String(input.prefix(maxLength))
    }
}
