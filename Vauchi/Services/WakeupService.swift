// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ADR-044 Am2a platform wakeup service.
//
// Core emits `Command::ScheduleWakeup { earliest_secs, deadline_secs,
// min_interval_secs }` whenever it needs the frontend to call back via
// `PlatformAppEngine.onWakeup()`. This service translates that relative
// schedule into a foreground `DispatchSourceTimer`. When the timer fires we
// invoke the registered `onWakeup` closure, which asks core for pending
// notifications/commands and dispatches them.
//
// Background wakeups are intentionally left to the existing
// `BackgroundSyncService` BGAppRefreshTask path; this service covers the
// foreground case requested by ADR-044 Am2a Option C.

import BackgroundTasks
import CoreUIModels
import Foundation
import VauchiPlatform

/// Notification payload inside the `PlatformAppEngine.onWakeup()` envelope.
/// Mirrors the JSON shape core emits without depending on the UniFFI
/// `MobilePendingNotification` type, which is not `Decodable`.
struct WakeupNotification: Decodable {
    let eventKey: String
    let category: String
    let title: String
    let body: String
    let contactId: String
    let deepLinkUri: String?
}

/// Envelope returned by `PlatformAppEngine.onWakeup()` (core!1379):
/// `{"notifications": [<WakeupNotification>], "commands": [<CommandDTO>]}`.
struct WakeupEnvelope: Decodable {
    let notifications: [WakeupNotification]
    let commands: [CommandDTO]
}

/// Schedules core-requested wakeups and fires the `onWakeup` callback.
@MainActor
final class WakeupService {
    static let shared = WakeupService()

    private var foregroundTimer: DispatchSourceTimer?
    private var lastWakeupAt: Date?
    private var onWakeup: (() -> Void)?

    private init() {}

    /// Wire the callback invoked when a scheduled wakeup fires.
    func setOnWakeup(_ callback: @escaping () -> Void) {
        onWakeup = callback
    }

    /// Arm a core-computed wakeup.
    ///
    /// - Parameters:
    ///   - earliestSecs: earliest time from now core wants us to call back.
    ///   - deadlineSecs: latest time from now core is willing to wait.
    ///   - minIntervalSecs: minimum spacing between two wakeup callbacks.
    func scheduleWakeup(earliestSecs: UInt32, deadlineSecs: UInt32, minIntervalSecs: UInt32) {
        // Honour the minimum interval by delaying to the earliest allowable
        // moment. This keeps the frontend from waking core more often than
        // core requested (e.g. multiple commands arriving in quick succession).
        var fireAfter = TimeInterval(earliestSecs)
        if minIntervalSecs > 0, let last = lastWakeupAt {
            let earliestNext = last.addingTimeInterval(TimeInterval(minIntervalSecs))
            let remaining = earliestNext.timeIntervalSinceNow
            if remaining > fireAfter {
                fireAfter = remaining
            }
        }

        // Clamp to the deadline so we never oversleep past what core asked.
        let deadline = TimeInterval(deadlineSecs)
        if fireAfter > deadline {
            fireAfter = deadline
        }

        foregroundTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + fireAfter)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            foregroundTimer = nil
            lastWakeupAt = Date()
            onWakeup?()
        }
        timer.resume()
        foregroundTimer = timer

        #if DEBUG
            print("WakeupService: scheduled wakeup in \(fireAfter)s")
        #endif
    }

    /// Cancel any pending foreground wakeup. Called when the app is
    /// backgrounded or when core no longer needs a wakeup.
    func cancelPendingWakeup() {
        foregroundTimer?.cancel()
        foregroundTimer = nil
    }
}
