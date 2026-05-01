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
        let createdAt = Date()
        let updatedAt = Date()
        let record = VauchiDeliveryRecord(
            messageId: "msg-123",
            recipientId: "contact-456",
            status: .delivered,
            createdAt: createdAt,
            updatedAt: updatedAt,
            expiresAt: nil
        )

        XCTAssertEqual(record.messageId, "msg-123")
        XCTAssertEqual(record.recipientId, "contact-456")
        XCTAssertEqual(record.status, .delivered)
        XCTAssertEqual(record.createdAt, createdAt)
        XCTAssertEqual(record.updatedAt, updatedAt)
        XCTAssertNil(record.expiresAt, "expiresAt was passed as nil")
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

        XCTAssertEqual(record.expiresAt, expiresAt)
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
        let repository = try VauchiRepository(dataDir: tempDir.path)
        try repository.createIdentity(displayName: "Alice")

        let records = try repository.getDeliveryRecordsForContact(contactId: "test-contact")

        // Should return empty array (no records yet)
        XCTAssertTrue(records.isEmpty)
    }

    /// Scenario: Repository gets delivery summary
    func testRepositoryGetDeliverySummary() throws {
        let repository = try VauchiRepository(dataDir: tempDir.path)
        try repository.createIdentity(displayName: "Alice")

        // For a non-existent message, the summary returns the queried id
        // with all device counters at zero — never throws, never invents
        // delivery records.
        let summary = try repository.getDeliverySummary(messageId: "nonexistent")

        XCTAssertEqual(summary.messageId, "nonexistent")
        XCTAssertEqual(summary.totalDevices, 0)
        XCTAssertEqual(summary.deliveredDevices, 0)
        XCTAssertEqual(summary.pendingDevices, 0)
        XCTAssertEqual(summary.failedDevices, 0)
        XCTAssertFalse(summary.isFullyDelivered, "Empty summary cannot be fully delivered")
    }

    /// Scenario: Repository can retry failed delivery
    func testRepositoryRetryDelivery() throws {
        let repository = try VauchiRepository(dataDir: tempDir.path)
        try repository.createIdentity(displayName: "Alice")

        // Retrying non-existent message should return false
        let result = try repository.retryDelivery(messageId: "nonexistent")

        XCTAssertFalse(result)
    }
}
