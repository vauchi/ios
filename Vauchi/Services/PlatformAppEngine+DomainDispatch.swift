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

    // MARK: - Contact CRUD (C2)

    func listContacts() throws -> [MobileContact] {
        let result = try dispatchDomainCommand(command: .listContacts)
        guard case let .contacts(contacts) = result else {
            throw MobileError.Other(
                detail: "ListContacts: unexpected result variant"
            )
        }
        return contacts
    }

    func listContactsPaginated(offset: UInt32, limit: UInt32) throws -> [MobileContact] {
        let result = try dispatchDomainCommand(
            command: .listContactsPaginated(offset: offset, limit: limit)
        )
        guard case let .contacts(contacts) = result else {
            throw MobileError.Other(
                detail: "ListContactsPaginated: unexpected result variant"
            )
        }
        return contacts
    }

    func getContact(id: String) throws -> MobileContact? {
        let result = try dispatchDomainCommand(command: .getContact(id: id))
        guard case let .contactOpt(contact) = result else {
            throw MobileError.Other(
                detail: "GetContact: unexpected result variant"
            )
        }
        return contact
    }

    func searchContacts(query: String) throws -> [MobileContact] {
        let result = try dispatchDomainCommand(command: .searchContacts(query: query))
        guard case let .contacts(contacts) = result else {
            throw MobileError.Other(
                detail: "SearchContacts: unexpected result variant"
            )
        }
        return contacts
    }

    func contactCount() throws -> UInt32 {
        let result = try dispatchDomainCommand(command: .contactCount)
        guard case let .count(value) = result else {
            throw MobileError.Other(
                detail: "ContactCount: unexpected result variant"
            )
        }
        return value
    }

    func removeContact(id: String) throws -> Bool {
        let result = try dispatchDomainCommand(command: .removeContact(id: id))
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "RemoveContact: unexpected result variant"
            )
        }
        return value
    }

    func softDeleteImportedContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .softDeleteImportedContact(id: id))
    }

    func undoDeleteImportedContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .undoDeleteImportedContact(id: id))
    }

    func hardDeleteImportedContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .hardDeleteImportedContact(id: id))
    }

    func archiveContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .archiveContact(id: id))
    }

    func unarchiveContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .unarchiveContact(id: id))
    }

    func listArchivedContacts() throws -> [MobileContact] {
        let result = try dispatchDomainCommand(command: .listArchivedContacts)
        guard case let .contacts(contacts) = result else {
            throw MobileError.Other(
                detail: "ListArchivedContacts: unexpected result variant"
            )
        }
        return contacts
    }

    func hideContact(contactId: String) throws {
        _ = try dispatchDomainCommand(command: .hideContact(contactId: contactId))
    }

    func unhideContact(contactId: String) throws {
        _ = try dispatchDomainCommand(command: .unhideContact(contactId: contactId))
    }

    // MARK: - Contact Verification (C2)

    func verifyContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .verifyContact(id: id))
    }

    func setProposalTrusted(contactId: String, trusted: Bool) throws {
        _ = try dispatchDomainCommand(
            command: .setProposalTrusted(contactId: contactId, trusted: trusted)
        )
    }

    func getOwnFingerprint() throws -> String {
        let result = try dispatchDomainCommand(command: .getOwnFingerprint)
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "GetOwnFingerprint: unexpected result variant"
            )
        }
        return value
    }

    // MARK: - Contact Notes (C2)

    func setContactNote(contactId: String, note: String) throws {
        _ = try dispatchDomainCommand(
            command: .setContactNote(contactId: contactId, note: note)
        )
    }

    func getContactNote(contactId: String) throws -> String? {
        let result = try dispatchDomainCommand(command: .getContactNote(contactId: contactId))
        guard case let .stringOpt(value) = result else {
            throw MobileError.Other(
                detail: "GetContactNote: unexpected result variant"
            )
        }
        return value
    }

    func deleteContactNote(contactId: String) throws {
        _ = try dispatchDomainCommand(command: .deleteContactNote(contactId: contactId))
    }

    func setContactFieldNote(contactId: String, fieldId: String, note: String) throws {
        _ = try dispatchDomainCommand(
            command: .setContactFieldNote(contactId: contactId, fieldId: fieldId, note: note)
        )
    }

    func getContactFieldNotes(contactId: String) throws -> [MobileFieldNote] {
        let result = try dispatchDomainCommand(command: .getContactFieldNotes(contactId: contactId))
        guard case let .fieldNotes(notes) = result else {
            throw MobileError.Other(
                detail: "GetContactFieldNotes: unexpected result variant"
            )
        }
        return notes
    }

    func deleteContactFieldNote(contactId: String, fieldId: String) throws {
        _ = try dispatchDomainCommand(
            command: .deleteContactFieldNote(contactId: contactId, fieldId: fieldId)
        )
    }

    // MARK: - Field Visibility (C3)

    func hideFieldFromContact(contactId: String, fieldLabel: String) throws {
        _ = try dispatchDomainCommand(
            command: .hideFieldFromContact(contactId: contactId, fieldLabel: fieldLabel)
        )
    }

    func showFieldToContact(contactId: String, fieldLabel: String) throws {
        _ = try dispatchDomainCommand(
            command: .showFieldToContact(contactId: contactId, fieldLabel: fieldLabel)
        )
    }

    func isFieldVisibleToContact(contactId: String, fieldLabel: String) throws -> Bool {
        let result = try dispatchDomainCommand(
            command: .isFieldVisibleToContact(contactId: contactId, fieldLabel: fieldLabel)
        )
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsFieldVisibleToContact: unexpected result variant"
            )
        }
        return value
    }

    // MARK: - Visibility Labels (C3)

    func listLabels() throws -> [MobileVisibilityLabel] {
        let result = try dispatchDomainCommand(command: .listLabels)
        guard case let .labels(labels) = result else {
            throw MobileError.Other(
                detail: "ListLabels: unexpected result variant"
            )
        }
        return labels
    }

    func createLabel(name: String) throws -> MobileVisibilityLabel {
        let result = try dispatchDomainCommand(command: .createLabel(name: name))
        guard case let .label(label) = result else {
            throw MobileError.Other(
                detail: "CreateLabel: unexpected result variant"
            )
        }
        return label
    }

    func getLabel(labelId: String) throws -> MobileVisibilityLabelDetail {
        let result = try dispatchDomainCommand(command: .getLabel(labelId: labelId))
        guard case let .labelDetail(detail) = result else {
            throw MobileError.Other(
                detail: "GetLabel: unexpected result variant"
            )
        }
        return detail
    }

    func renameLabel(labelId: String, newName: String) throws {
        _ = try dispatchDomainCommand(
            command: .renameLabel(labelId: labelId, newName: newName)
        )
    }

    func deleteLabel(labelId: String) throws {
        _ = try dispatchDomainCommand(command: .deleteLabel(labelId: labelId))
    }

    func addContactToGroup(labelId: String, contactId: String) throws {
        _ = try dispatchDomainCommand(
            command: .addContactToGroup(labelId: labelId, contactId: contactId)
        )
    }

    func removeContactFromGroup(labelId: String, contactId: String) throws {
        _ = try dispatchDomainCommand(
            command: .removeContactFromGroup(labelId: labelId, contactId: contactId)
        )
    }

    func getGroupsForContact(contactId: String) throws -> [MobileVisibilityLabel] {
        let result = try dispatchDomainCommand(
            command: .getGroupsForContact(contactId: contactId)
        )
        guard case let .labels(labels) = result else {
            throw MobileError.Other(
                detail: "GetGroupsForContact: unexpected result variant"
            )
        }
        return labels
    }

    func setGroupFieldVisibility(labelId: String, fieldLabel: String, isVisible: Bool) throws {
        _ = try dispatchDomainCommand(
            command: .setGroupFieldVisibility(
                labelId: labelId, fieldLabel: fieldLabel, isVisible: isVisible
            )
        )
    }

    func getSuggestedLabels() throws -> [String] {
        let result = try dispatchDomainCommand(command: .getSuggestedLabels)
        guard case let .strings(values) = result else {
            throw MobileError.Other(
                detail: "GetSuggestedLabels: unexpected result variant"
            )
        }
        return values
    }
}
