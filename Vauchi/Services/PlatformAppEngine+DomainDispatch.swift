// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import VauchiPlatform

extension PlatformAppEngine {
    // MARK: - Identity / Bootstrap (C1)

    func createIdentity(displayName: String) throws {
        _ = try dispatchDomainCommand(
            command: .createIdentity(displayName: displayName)
        )
    }

    func getPublicId() throws -> String {
        let result = try dispatchDomainCommand(command: .getPublicId)
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "GetPublicId: unexpected result variant"
            )
        }
        return value
    }

    func getDisplayName() throws -> String {
        let result = try dispatchDomainCommand(command: .getDisplayName)
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "GetDisplayName: unexpected result variant"
            )
        }
        return value
    }

    // MARK: - Contact Field Mutation (C1)

    func getOwnCard() throws -> MobileContactCard {
        let result = try dispatchDomainCommand(command: .getOwnCard)
        guard case let .contactCardPayload(card) = result else {
            throw MobileError.Other(
                detail: "GetOwnCard: unexpected result variant"
            )
        }
        return card
    }

    func addField(
        fieldType: MobileFieldType,
        label: String,
        value: String
    ) throws {
        _ = try dispatchDomainCommand(
            command: .addField(
                fieldType: fieldType,
                label: label,
                value: value
            )
        )
    }

    func updateField(label: String, newValue: String) throws {
        _ = try dispatchDomainCommand(
            command: .updateField(label: label, newValue: newValue)
        )
    }

    func removeField(label: String) throws -> Bool {
        let result = try dispatchDomainCommand(
            command: .removeField(label: label)
        )
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "RemoveField: unexpected result variant"
            )
        }
        return value
    }

    func setDisplayName(name: String) throws {
        _ = try dispatchDomainCommand(
            command: .setDisplayName(name: name)
        )
    }

    // MARK: - Backup (C5)

    func exportBackup(password: String) throws -> String {
        let result = try dispatchDomainCommand(
            command: .exportBackup(password: password)
        )
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "ExportBackup: unexpected result variant"
            )
        }
        return value
    }

    func importBackup(backupData: String, password: String) throws {
        _ = try dispatchDomainCommand(
            command: .importBackup(backupData: backupData, password: password)
        )
    }

    // MARK: - Delivery Records / Retry Queue (C4)

    func getAllDeliveryRecords() throws -> [MobileDeliveryRecord] {
        let result = try dispatchDomainCommand(command: .getAllDeliveryRecords)
        guard case let .deliveryRecords(records) = result else {
            throw MobileError.Other(
                detail: "GetAllDeliveryRecords: unexpected result variant"
            )
        }
        return records
    }

    func getFailedDeliveryRecords() throws -> [MobileDeliveryRecord] {
        let result = try dispatchDomainCommand(command: .getFailedDeliveryRecords)
        guard case let .deliveryRecords(records) = result else {
            throw MobileError.Other(
                detail: "GetFailedDeliveryRecords: unexpected result variant"
            )
        }
        return records
    }

    func getDeliveryRecordsForContact(recipientId: String) throws -> [MobileDeliveryRecord] {
        let result = try dispatchDomainCommand(
            command: .getDeliveryRecordsForContact(recipientId: recipientId)
        )
        guard case let .deliveryRecords(records) = result else {
            throw MobileError.Other(
                detail: "GetDeliveryRecordsForContact: unexpected result variant"
            )
        }
        return records
    }

    func getDeliverySummary(messageId: String) throws -> MobileDeliverySummary {
        let result = try dispatchDomainCommand(
            command: .getDeliverySummary(messageId: messageId)
        )
        guard case let .deliverySummary(summary) = result else {
            throw MobileError.Other(
                detail: "GetDeliverySummary: unexpected result variant"
            )
        }
        return summary
    }

    func getDueRetries() throws -> [MobileRetryEntry] {
        let result = try dispatchDomainCommand(command: .getDueRetries)
        guard case let .retryEntries(entries) = result else {
            throw MobileError.Other(
                detail: "GetDueRetries: unexpected result variant"
            )
        }
        return entries
    }

    func manualRetry(messageId: String) throws -> Bool {
        let result = try dispatchDomainCommand(
            command: .manualRetry(messageId: messageId)
        )
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "ManualRetry: unexpected result variant"
            )
        }
        return value
    }

    func countFailedDeliveries() throws -> UInt32 {
        let result = try dispatchDomainCommand(command: .countFailedDeliveries)
        guard case let .count(value) = result else {
            throw MobileError.Other(
                detail: "CountFailedDeliveries: unexpected result variant"
            )
        }
        return value
    }
}
