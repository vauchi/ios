// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// BackgroundSyncService.swift
// Background sync service using BGTaskScheduler for Vauchi iOS
// Schedules periodic sync tasks to keep contacts up-to-date

import BackgroundTasks
import Foundation
import VauchiPlatform

/// Service for managing background sync operations
final class BackgroundSyncService {
    // MARK: - Singleton

    static let shared = BackgroundSyncService()

    // MARK: - Constants

    /// Background task identifier (must match Info.plist)
    static let syncTaskIdentifier = "app.vauchi.sync"

    // MARK: - Private Properties

    private var syncHandler: (() async -> Void)?

    /// Engine used to query the core-owned scheduler interval.
    /// Set by the app at registration time (audit
    /// `2026-04-28-lifecycle-session-residue-umbrella` P2-C —
    /// the 15-min cadence is no longer a frontend constant).
    private var appEngine: PlatformAppEngine?

    /// Fallback interval used before the engine is wired
    /// (e.g. cold-start scheduling that runs before the
    /// repository is constructed). Matches core's
    /// `PERIODIC_SYNC_INTERVAL_SECONDS = 900`.
    private static let fallbackSyncIntervalSeconds: UInt64 = 900

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Register background tasks with the system
    /// Call this from application(_:didFinishLaunchingWithOptions:) or app init
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handleSyncTask(refreshTask)
        }
    }

    /// Wire the engine so the scheduler interval comes from core
    /// rather than from a frontend magic constant.
    func setAppEngine(_ engine: PlatformAppEngine) {
        appEngine = engine
    }

    /// Set the sync handler that will be called when background sync runs
    func setSyncHandler(_ handler: @escaping () async -> Void) {
        syncHandler = handler
    }

    /// Schedule the next sync task
    func scheduleSyncTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.syncTaskIdentifier)
        let intervalSeconds = appEngine?.periodicSyncIntervalSeconds() ?? Self.fallbackSyncIntervalSeconds
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalSeconds))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Log error but don't crash - background tasks may not be available
            // in all contexts (e.g., simulator, development)
            #if DEBUG
                print("BackgroundSyncService: Failed to schedule sync task: \(error)")
            #endif
        }
    }

    /// Cancel all pending sync tasks
    func cancelPendingTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.syncTaskIdentifier)
    }

    // MARK: - Private Methods

    private func handleSyncTask(_ task: BGAppRefreshTask) {
        // Schedule the next sync task before handling this one
        scheduleSyncTask()

        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Run the sync
        Task {
            if let handler = syncHandler {
                await handler()
                task.setTaskCompleted(success: true)
            } else {
                task.setTaskCompleted(success: false)
            }
        }
    }
}
