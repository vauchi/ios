// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Holds at most one instance, created by the first caller; a failed
/// creation is tried again by the next caller.
final class SharedInstance<T: AnyObject> {
    private let lock = NSLock()
    private var instance: T?

    func get(orMake make: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if let instance {
            return instance
        }
        let made = try make()
        instance = made
        return made
    }
}
