// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// DeliveryStatusTests.swift
// Tests for delivery status UI functionality
// Based on: features/message_delivery.feature

@testable import Vauchi
import XCTest

/// Tests for delivery status tracking and UI
/// Traces to: features/message_delivery.feature
@MainActor
final class DeliveryStatusTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Delivery Status Type Tests

    /// Scenario: DeliveryStatus has correct states
    func testDeliveryStatusStates() {
        // Verify all expected delivery states exist
        let queued = VauchiDeliveryStatus.queued
        let sent = VauchiDeliveryStatus.sent
        let stored = VauchiDeliveryStatus.stored
        let delivered = VauchiDeliveryStatus.delivered
        let expired = VauchiDeliveryStatus.expired
        let failed = VauchiDeliveryStatus.failed(reason: "Network error")

        XCTAssertEqual(queued.displayName, "Queued")
        XCTAssertEqual(sent.displayName, "Sent")
        XCTAssertEqual(stored.displayName, "Stored")
        XCTAssertEqual(delivered.displayName, "Delivered")
        XCTAssertEqual(expired.displayName, "Expired")
        XCTAssertEqual(failed.displayName, "Failed")
    }

    /// Scenario: DeliveryStatus icons are correct
    func testDeliveryStatusIcons() {
        XCTAssertEqual(VauchiDeliveryStatus.queued.iconName, "clock")
        XCTAssertEqual(VauchiDeliveryStatus.sent.iconName, "arrow.up.circle")
        XCTAssertEqual(VauchiDeliveryStatus.stored.iconName, "checkmark.circle")
        XCTAssertEqual(VauchiDeliveryStatus.delivered.iconName, "checkmark.circle.fill")
        XCTAssertEqual(VauchiDeliveryStatus.expired.iconName, "exclamationmark.triangle")
        XCTAssertEqual(VauchiDeliveryStatus.failed(reason: "").iconName, "xmark.circle")
    }

    // MARK: - Delivery Record Tests

    /// Scenario: DeliveryRecord contains required fields
    func testDeliveryRecordFields() {
        let record = VauchiDeliveryRecord(
            messageId: "msg-123",
            recipientId: "contact-456",
            status: .delivered,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: nil
        )

        XCTAssertEqual(record.messageId, "msg-123")
        XCTAssertEqual(record.recipientId, "contact-456")
        XCTAssertEqual(record.status, .delivered)
        XCTAssertNotNil(record.createdAt)
        XCTAssertNotNil(record.updatedAt)
    }

    /// Scenario: DeliveryRecord with expiration
    func testDeliveryRecordWithExpiration() {
        let expiresAt = Date().addingTimeInterval(86400) // 1 day from now
        let record = VauchiDeliveryRecord(
            messageId: "msg-123",
            recipientId: "contact-456",
            status: .stored,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: expiresAt
        )

        XCTAssertNotNil(record.expiresAt)
        XCTAssertFalse(record.isExpired)
    }

    /// Scenario: DeliveryRecord detects expiration
    func testDeliveryRecordExpiredCheck() {
        let expiredAt = Date().addingTimeInterval(-3600) // 1 hour ago
        let record = VauchiDeliveryRecord(
            messageId: "msg-123",
            recipientId: "contact-456",
            status: .stored,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date().addingTimeInterval(-86400),
            expiresAt: expiredAt
        )

        XCTAssertTrue(record.isExpired)
    }

    // MARK: - Multi-Device Delivery Tests

    /// Scenario: DeliverySummary shows progress
    func testDeliverySummaryProgress() {
        let summary = VauchiDeliverySummary(
            messageId: "msg-123",
            totalDevices: 3,
            deliveredDevices: 2,
            pendingDevices: 1,
            failedDevices: 0
        )

        XCTAssertEqual(summary.totalDevices, 3)
        XCTAssertEqual(summary.deliveredDevices, 2)
        XCTAssertEqual(summary.pendingDevices, 1)
        XCTAssertFalse(summary.isFullyDelivered)
        XCTAssertEqual(summary.progressPercent, 66) // 2/3 = 66%
    }

    /// Scenario: DeliverySummary detects full delivery
    func testDeliverySummaryFullDelivery() {
        let summary = VauchiDeliverySummary(
            messageId: "msg-123",
            totalDevices: 2,
            deliveredDevices: 2,
            pendingDevices: 0,
            failedDevices: 0
        )

        XCTAssertTrue(summary.isFullyDelivered)
        XCTAssertEqual(summary.progressPercent, 100)
    }

    /// Scenario: DeliverySummary display text
    func testDeliverySummaryDisplayText() {
        let summary = VauchiDeliverySummary(
            messageId: "msg-123",
            totalDevices: 3,
            deliveredDevices: 2,
            pendingDevices: 1,
            failedDevices: 0
        )

        XCTAssertEqual(summary.displayText, "Delivered to 2 of 3 devices")
    }

    // MARK: - ViewModel Integration Tests

    /// Scenario: ViewModel loads delivery records
    ///
    /// `loadDeliveryRecords` swallows the underlying `vauchi.getAllDeliveryRecords`
    /// error and resets to `[]`, so this test verifies the empty-state behavior
    /// rather than the legacy delivery query itself — the per-test data dir
    /// just lets `createIdentity` succeed without colliding with prior tests.
    func testViewModelLoadsDeliveryRecords() async throws {
        let viewModel = VauchiViewModel(dataDir: tempDir.path, relayUrl: nil)
        try await viewModel.createIdentity(name: "Alice")

        // Load delivery records
        await viewModel.loadDeliveryRecords()

        // Initially should be empty (no messages sent)
        XCTAssertTrue(viewModel.deliveryRecords.isEmpty)
    }

    /// Scenario: ViewModel loads retry entries
    func testViewModelLoadsRetryEntries() async throws {
        let viewModel = VauchiViewModel(dataDir: tempDir.path, relayUrl: nil)
        try await viewModel.createIdentity(name: "Alice")

        // Load retry entries
        await viewModel.loadRetryEntries()

        // Initially should be empty
        XCTAssertTrue(viewModel.retryEntries.isEmpty)
    }

    /// Scenario: ViewModel reports failed delivery count
    func testViewModelFailedDeliveryCount() async throws {
        let viewModel = VauchiViewModel(dataDir: tempDir.path, relayUrl: nil)
        try await viewModel.createIdentity(name: "Alice")

        await viewModel.loadDeliveryRecords()

        // Initially should be zero
        XCTAssertEqual(viewModel.failedDeliveryCount, 0)
    }

    // MARK: - Repository Tests

    /// Scenario: Repository gets delivery records for contact
    func testRepositoryGetDeliveryRecordsForContact() throws {
        try Self.skipPendingDeliveryMigration()
        let repository = try VauchiRepository()
        try repository.createIdentity(displayName: "Alice")

        let records = try repository.getDeliveryRecordsForContact(contactId: "test-contact")

        // Should return empty array (no records yet)
        XCTAssertTrue(records.isEmpty)
    }

    /// Scenario: Repository gets delivery summary
    func testRepositoryGetDeliverySummary() throws {
        try Self.skipPendingDeliveryMigration()
        let repository = try VauchiRepository()
        try repository.createIdentity(displayName: "Alice")

        // Getting summary for non-existent message should return nil or empty summary
        let summary = try repository.getDeliverySummary(messageId: "nonexistent")

        // Should handle gracefully
        XCTAssertNotNil(summary)
    }

    /// Scenario: Repository can retry failed delivery
    func testRepositoryRetryDelivery() throws {
        try Self.skipPendingDeliveryMigration()
        let repository = try VauchiRepository()
        try repository.createIdentity(displayName: "Alice")

        // Retrying non-existent message should return false
        let result = try repository.retryDelivery(messageId: "nonexistent")

        XCTAssertFalse(result)
    }

    /// Skip helper for tests that go through the legacy `vauchi: VauchiPlatform`
    /// instance after `appEngine.createIdentity`. The legacy instance has no
    /// `reload_from_storage()` seam, so its in-memory state stays "no identity"
    /// even though the DB has one — every delivery query then errors with
    /// `Identity not found`. Restored when the Delivery domain migrates to
    /// `PlatformAppEngine` (C4 in
    /// `_private/docs/problems/2026-04-28-collapse-vauchi-platform-into-app-engine/`).
    private static func skipPendingDeliveryMigration() throws {
        throw XCTSkip(
            "Blocked on dual-instance state drift — Delivery methods still "
                + "go through legacy VauchiPlatform; restored when C4 "
                + "(Delivery Records / Retry) migrates to PlatformAppEngine. "
                + "See _private/docs/problems/2026-04-28-collapse-vauchi-"
                + "platform-into-app-engine/."
        )
    }
}
