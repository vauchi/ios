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
    /// The last schedule core asked for, replayed by `rearmWithLastRequest`
    /// when a tick fails to produce a new one.
    private var lastRequest: (
        earliest: UInt32,
        deadline: UInt32,
        minInterval: UInt32,
        millis: UInt32?
    )?
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
    func scheduleWakeup(
        earliestSecs: UInt32,
        deadlineSecs: UInt32,
        minIntervalSecs: UInt32,
        earliestMillis: UInt32? = nil
    ) {
        // Honour the minimum interval by delaying to the earliest allowable
        // moment. This keeps the frontend from waking core more often than
        // core requested (e.g. multiple commands arriving in quick succession).
        // Seconds cannot express the frame dwell of a live exchange, whose QR
        // advances from this timer. Android read only the whole-second field
        // and ran at 1013 ms against a ~300 ms design; this is the same field,
        // on the same command
        // (2026-08-18-hover-transfer-stalls-on-the-last-chunk).
        var fireAfter =
            earliestMillis.map { TimeInterval($0) / 1000.0 } ?? TimeInterval(earliestSecs)
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
        lastRequest = (earliestSecs, deadlineSecs, minIntervalSecs, earliestMillis)

        #if DEBUG
            print("WakeupService: scheduled wakeup in \(fireAfter)s")
        #endif
    }

    /// Re-arm on the terms core last asked for.
    ///
    /// The wakeup is a single-fire timer whose successor is only armed by a
    /// `ScheduleWakeup` coming back from the tick, so any failure — a decode
    /// error, an empty command list — used to leave it unarmed forever and
    /// freeze the exchange on whatever frame was last drawn. Android cannot
    /// do this: its loop catches, falls back and continues. Repeating core's
    /// last instruction keeps that property here without inventing a cadence
    /// core did not ask for.
    func rearmWithLastRequest() {
        guard let last = lastRequest else { return }
        // Carries the sub-second value too: replaying only the whole-second
        // field would quietly drop a live exchange back to one frame a second
        // the first time a tick failed.
        scheduleWakeup(
            earliestSecs: last.earliest,
            deadlineSecs: last.deadline,
            minIntervalSecs: last.minInterval,
            earliestMillis: last.millis
        )
    }

    /// Cancel any pending foreground wakeup. Called when the app is
    /// backgrounded or when core no longer needs a wakeup.
    func cancelPendingWakeup() {
        foregroundTimer?.cancel()
        foregroundTimer = nil
    }

    /// Test-only accessor — true while a foreground wakeup is armed.
    var hasScheduledWakeup: Bool {
        foregroundTimer != nil
    }
}
