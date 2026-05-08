// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AppDelegate.swift
// Minimal UIApplicationDelegate that exists only to gate
// `supportedInterfaceOrientationsFor` on the `OrientationLock`
// singleton. SwiftUI does not expose this hook directly.
//
// Phase 2c of `2026-05-04-exchange-command-screen-presentation`:
// `Command::SetOrientationLock` flips `OrientationLock.shared`,
// UIKit then re-queries this delegate, and the device clamps
// to the requested mask.

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor _: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if let mask = OrientationLock.shared.lockedMask {
            return mask
        }
        return [.portrait, .landscape]
    }
}
