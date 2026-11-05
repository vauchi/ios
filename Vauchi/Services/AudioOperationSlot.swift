// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

final class AudioOperationSlot {
    final class Request {}

    private final class Operation {
        let stop: () -> Void
        let interrupted = DispatchSemaphore(value: 0)
        init(stop: @escaping () -> Void) {
            self.stop = stop
        }
    }

    private let lock = NSRecursiveLock()
    private var current: Operation?
    private var latest: Request?

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return current != nil
    }

    func reserve() -> Request {
        lock.lock()
        defer { lock.unlock() }
        let request = Request()
        latest = request
        current?.interrupted.signal()
        return request
    }

    @discardableResult
    func deliver(_ request: Request, body: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard latest === request else { return false }
        body()
        return true
    }

    func run(
        for duration: TimeInterval,
        request: Request? = nil,
        start: () throws -> Void,
        stop: @escaping () -> Void
    ) rethrows {
        lock.lock()
        let request = request ?? reserve()
        guard latest === request else {
            lock.unlock()
            return
        }
        cancelCurrent()
        let operation = Operation(stop: stop)
        current = operation
        do {
            try start()
        } catch {
            cancelCurrent()
            lock.unlock()
            throw error
        }
        lock.unlock()
        _ = operation.interrupted.wait(timeout: .now() + max(0, duration))
        lock.lock()
        defer { lock.unlock() }
        if current === operation {
            cancelCurrent()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        latest = nil
        cancelCurrent()
    }

    private func cancelCurrent() {
        guard let operation = current else { return }
        current = nil
        operation.stop()
        operation.interrupted.signal()
    }
}
