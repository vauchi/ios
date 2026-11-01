// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Core's canonical `Event::PermissionGranted` for a prompt the shell raised
/// itself. The generated `MobileEvent` has no such case, so the grant goes as
/// event JSON (vauchi/private#1022).
enum PermissionGrantEvent {
    static func json(transport: String) -> String {
        let event = ["PermissionGranted": ["transport": transport]]
        guard let data = try? JSONSerialization.data(withJSONObject: event) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
