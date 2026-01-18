// BackgroundSyncService.swift
// Background sync service using BGTaskScheduler for Vauchi iOS
// Schedules periodic sync tasks to keep contacts up-to-date

import Foundation
import BackgroundTasks

/// Service for managing background sync operations
final class BackgroundSyncService {
    // MARK: - Singleton

    static let shared = BackgroundSyncService()

    // MARK: - Constants

    /// Background task identifier (must match Info.plist)
    static let syncTaskIdentifier = "app.vauchi.sync"

    /// Minimum interval between sync tasks (15 minutes)
    private static let syncInterval: TimeInterval = 15 * 60

    // MARK: - Private Properties

    private var syncHandler: (() async -> Void)?

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
            self?.handleSyncTask(task as! BGProcessingTask)
        }
    }

    /// Set the sync handler that will be called when background sync runs
    func setSyncHandler(_ handler: @escaping () async -> Void) {
        self.syncHandler = handler
    }

    /// Schedule the next sync task
    func scheduleSyncTask() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.syncInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Log error but don't crash - background tasks may not be available
            // in all contexts (e.g., simulator, development)
            print("BackgroundSyncService: Failed to schedule sync task: \(error)")
        }
    }

    /// Cancel all pending sync tasks
    func cancelPendingTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.syncTaskIdentifier)
    }

    // MARK: - Private Methods

    private func handleSyncTask(_ task: BGProcessingTask) {
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
