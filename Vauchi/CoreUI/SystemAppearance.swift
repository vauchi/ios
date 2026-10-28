// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit

/// The OS light/dark setting, read from the window scene rather than the
/// view environment: the window takes the active theme's style
/// (`PresentationPalette.appearance`), so its own `colorScheme` stops
/// saying what the OS is set to, and Core needs the OS value for
/// "follow system" (vauchi/private#814).
@MainActor
final class SystemAppearance: ObservableObject {
    @Published private(set) var colorScheme: PresentationColorScheme
    private var traitRegistration: Any?
    private var activeObserver: NSObjectProtocol?

    init() {
        colorScheme = Self.current()
        if #available(iOS 17.0, *), let scene = Self.scene {
            traitRegistration = scene.registerForTraitChanges(
                [UITraitUserInterfaceStyle.self]
            ) { [weak self] (scene: UIWindowScene, _: UITraitCollection) in
                self?.colorScheme = Self.scheme(of: scene.traitCollection)
            }
        }
        // iOS 15 and 16 have no trait registration; the OS setting changes
        // in Settings or Control Center, both of which leave the app.
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.colorScheme = Self.current()
            }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    }

    private static func current() -> PresentationColorScheme {
        scheme(of: scene?.traitCollection ?? UIScreen.main.traitCollection)
    }

    private static func scheme(of traits: UITraitCollection) -> PresentationColorScheme {
        traits.userInterfaceStyle == .dark ? .dark : .light
    }
}
