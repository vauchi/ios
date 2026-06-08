// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Bridge between core's `Command::SetOrientationLock` and UIKit's
// `application(_:supportedInterfaceOrientationsFor:)` delegate hook.
//
// Phase 2c of `2026-05-04-exchange-command-screen-presentation`:
// frontends are pure renderers (ADR-021/043) — they translate the
// core-emitted command into the platform-native surface. On iOS
// that surface is the AppDelegate gate, so we keep a singleton mask
// that the delegate consults at orientation-validation time.

import CoreUIModels
import UIKit

@MainActor
final class OrientationLock {
    static let shared = OrientationLock()

    /// `nil` means "no lock — accept the Info.plist default mask".
    /// Non-`nil` clamps the supported orientations to that mask.
    private(set) var lockedMask: UIInterfaceOrientationMask?

    private init() {}

    func setMask(_ mask: UIInterfaceOrientationMask?) {
        lockedMask = mask
        // Re-evaluate the active scene so UIKit asks the delegate
        // again and rotates if the current orientation is now
        // disallowed.
        if #available(iOS 16.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                let prefs = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: mask ?? [.portrait, .landscape]
                )
                windowScene.requestGeometryUpdate(prefs) { _ in }
            }
            for scene in UIApplication.shared.connectedScenes {
                guard let root = (scene as? UIWindowScene)?
                    .windows.first?.rootViewController else { continue }
                root.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

extension OrientationDTO {
    var uiKitMask: UIInterfaceOrientationMask {
        switch self {
        case .portrait: .portrait
        case .landscape: .landscape
        }
    }
}
