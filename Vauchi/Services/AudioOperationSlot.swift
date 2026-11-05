// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

final class AudioOperationSlot {
    private final class Operation {
        let stop: () -> Void
        init(stop: @escaping () -> Void) {
            self.stop = stop
        }
    }

    private let condition = NSCondition()
    private var current: Operation?

    var isActive: Bool {
        condition.lock()
        defer { condition.unlock() }
        return current != nil
    }

    func run(for duration: TimeInterval, start: () throws -> Void, stop: @escaping () -> Void) rethrows {
        condition.lock()
        defer { condition.unlock() }
        cancelCurrent()
        let operation = Operation(stop: stop)
        current = operation
        do {
            try start()
        } catch {
            cancelCurrent()
            throw error
        }
        let deadline = Date(timeIntervalSinceNow: max(0, duration))
        while current === operation {
            if !condition.wait(until: deadline) {
                break
            }
        }
        if current === operation {
            cancelCurrent()
        }
    }

    func stop() {
        condition.lock()
        defer { condition.unlock() }
        cancelCurrent()
    }

    private func cancelCurrent() {
        guard let operation = current else { return }
        current = nil
        operation.stop()
        condition.broadcast()
    }
}
