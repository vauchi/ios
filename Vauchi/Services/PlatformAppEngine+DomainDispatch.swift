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

    func exportFullBackup(password: String) throws -> String {
        let result = try dispatchDomainCommand(
            command: .exportFullBackup(password: password)
        )
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "ExportFullBackup: unexpected result variant"
            )
        }
        return value
    }

    func importFullBackup(backupData: String, password: String) throws {
        _ = try dispatchDomainCommand(
            command: .importFullBackup(backupData: backupData, password: password)
        )
    }

    // MARK: - Decoy Contacts (B7 batch 7)

    func addDecoyContact(name: String, cardJson: String) throws -> String {
        let result = try dispatchDomainCommand(
            command: .addDecoyContact(name: name, cardJson: cardJson)
        )
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "AddDecoyContact: unexpected result variant"
            )
        }
        return value
    }

    func listDecoyContacts() throws -> [MobileDecoyContact] {
        let result = try dispatchDomainCommand(command: .listDecoyContacts)
        guard case let .decoyContacts(contacts) = result else {
            throw MobileError.Other(
                detail: "ListDecoyContacts: unexpected result variant"
            )
        }
        return contacts
    }

    func deleteDecoyContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .deleteDecoyContact(id: id))
    }

    // MARK: - Sync Flags (B7 batch 18)

    func isDeliveryReceiptsEnabled() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isDeliveryReceiptsEnabled)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsDeliveryReceiptsEnabled: unexpected result variant"
            )
        }
        return value
    }

    func setDeliveryReceiptsEnabled(enabled: Bool) throws {
        _ = try dispatchDomainCommand(
            command: .setDeliveryReceiptsEnabled(enabled: enabled)
        )
    }

    func isSuppressPresenceEnabled() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isSuppressPresenceEnabled)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsSuppressPresenceEnabled: unexpected result variant"
            )
        }
        return value
    }

    func setSuppressPresenceEnabled(enabled: Bool) throws {
        _ = try dispatchDomainCommand(
            command: .setSuppressPresenceEnabled(enabled: enabled)
        )
    }

    // MARK: - Pending Updates (B7 batch 13)

    func pendingUpdateCount() throws -> UInt32 {
        let result = try dispatchDomainCommand(command: .pendingUpdateCount)
        guard case let .count(value) = result else {
            throw MobileError.Other(
                detail: "PendingUpdateCount: unexpected result variant"
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

    func archiveContact(id: String) throws {
        _ = try dispatchDomainCommand(command: .archiveContact(id: id))
    }

    func hideContact(contactId: String) throws {
        _ = try dispatchDomainCommand(command: .hideContact(contactId: contactId))
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

    // MARK: - Demo Contact (C8 partial)

    func initDemoContactIfNeeded() throws -> MobileDemoContact? {
        let result = try dispatchDomainCommand(command: .initDemoContactIfNeeded)
        guard case let .demoContactOpt(contact) = result else {
            throw MobileError.Other(
                detail: "InitDemoContactIfNeeded: unexpected result variant"
            )
        }
        return contact
    }

    func getDemoContact() throws -> MobileDemoContact? {
        let result = try dispatchDomainCommand(command: .getDemoContact)
        guard case let .demoContactOpt(contact) = result else {
            throw MobileError.Other(
                detail: "GetDemoContact: unexpected result variant"
            )
        }
        return contact
    }

    func getDemoContactState() throws -> MobileDemoContactState {
        let result = try dispatchDomainCommand(command: .getDemoContactState)
        guard case let .demoContactState(state) = result else {
            throw MobileError.Other(
                detail: "GetDemoContactState: unexpected result variant"
            )
        }
        return state
    }

    func isDemoUpdateAvailable() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isDemoUpdateAvailable)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsDemoUpdateAvailable: unexpected result variant"
            )
        }
        return value
    }

    func triggerDemoUpdate() throws -> MobileDemoContact? {
        let result = try dispatchDomainCommand(command: .triggerDemoUpdate)
        guard case let .demoContactOpt(contact) = result else {
            throw MobileError.Other(
                detail: "TriggerDemoUpdate: unexpected result variant"
            )
        }
        return contact
    }

    func dismissDemoContact() throws {
        _ = try dispatchDomainCommand(command: .dismissDemoContact)
    }

    func autoRemoveDemoContact() throws -> Bool {
        let result = try dispatchDomainCommand(command: .autoRemoveDemoContact)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "AutoRemoveDemoContact: unexpected result variant"
            )
        }
        return value
    }

    func restoreDemoContact() throws -> MobileDemoContact? {
        let result = try dispatchDomainCommand(command: .restoreDemoContact)
        guard case let .demoContactOpt(contact) = result else {
            throw MobileError.Other(
                detail: "RestoreDemoContact: unexpected result variant"
            )
        }
        return contact
    }

    // MARK: - Social Networks (C8 partial)

    func listSocialNetworks() throws -> [MobileSocialNetwork] {
        let result = try dispatchDomainCommand(command: .listSocialNetworks)
        guard case let .socialNetworks(networks) = result else {
            throw MobileError.Other(
                detail: "ListSocialNetworks: unexpected result variant"
            )
        }
        return networks
    }

    func searchSocialNetworks(query: String) throws -> [MobileSocialNetwork] {
        let result = try dispatchDomainCommand(command: .searchSocialNetworks(query: query))
        guard case let .socialNetworks(networks) = result else {
            throw MobileError.Other(
                detail: "SearchSocialNetworks: unexpected result variant"
            )
        }
        return networks
    }

    func getProfileUrl(networkId: String, username: String) throws -> String? {
        let result = try dispatchDomainCommand(
            command: .getProfileUrl(networkId: networkId, username: username)
        )
        guard case let .stringOpt(value) = result else {
            throw MobileError.Other(
                detail: "GetProfileUrl: unexpected result variant"
            )
        }
        return value
    }

    func reloadSocialNetworks() throws -> [MobileSocialNetwork] {
        let result = try dispatchDomainCommand(command: .reloadSocialNetworks)
        guard case let .socialNetworks(networks) = result else {
            throw MobileError.Other(
                detail: "ReloadSocialNetworks: unexpected result variant"
            )
        }
        return networks
    }

    // MARK: - Content Updates (C8 partial)

    func isContentUpdatesSupported() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isContentUpdatesSupported)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsContentUpdatesSupported: unexpected result variant"
            )
        }
        return value
    }

    func checkContentUpdates() throws -> MobileUpdateStatus {
        let result = try dispatchDomainCommand(command: .checkContentUpdates)
        guard case let .updateStatus(status) = result else {
            throw MobileError.Other(
                detail: "CheckContentUpdates: unexpected result variant"
            )
        }
        return status
    }

    func applyContentUpdates() throws -> MobileApplyResult {
        let dispatched = try dispatchDomainCommand(command: .applyContentUpdates)
        guard case let .applyResult(result) = dispatched else {
            throw MobileError.Other(
                detail: "ApplyContentUpdates: unexpected result variant"
            )
        }
        return result
    }

    // MARK: - Certificate Pinning (C8 partial)

    func isCertificatePinningEnabled() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isCertificatePinningEnabled)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsCertificatePinningEnabled: unexpected result variant"
            )
        }
        return value
    }

    func setPinnedCertificate(certPem: String) throws {
        _ = try dispatchDomainCommand(command: .setPinnedCertificate(certPem: certPem))
    }

    // MARK: - Passcode (C6)

    func setupAppPassword(password: String) throws {
        _ = try dispatchDomainCommand(command: .setupAppPassword(password: password))
    }

    func authenticate(password: String) throws -> MobileAuthMode {
        let result = try dispatchDomainCommand(command: .authenticate(password: password))
        guard case let .authMode(mode) = result else {
            throw MobileError.Other(
                detail: "Authenticate: unexpected result variant"
            )
        }
        return mode
    }

    func isPasswordEnabled() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isPasswordEnabled)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsPasswordEnabled: unexpected result variant"
            )
        }
        return value
    }

    // MARK: - Duress (C6)

    func setupDuressPassword(duressPassword: String) throws {
        _ = try dispatchDomainCommand(
            command: .setupDuressPassword(duressPassword: duressPassword)
        )
    }

    func isDuressEnabled() throws -> Bool {
        let result = try dispatchDomainCommand(command: .isDuressEnabled)
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "IsDuressEnabled: unexpected result variant"
            )
        }
        return value
    }

    func disableDuress() throws {
        _ = try dispatchDomainCommand(command: .disableDuress)
    }

    func configureDuressAlerts(contactIds: [String], message: String) throws {
        _ = try dispatchDomainCommand(
            command: .configureDuressAlerts(contactIds: contactIds, message: message)
        )
    }

    func getDuressSettings() throws -> MobileDuressSettings? {
        let result = try dispatchDomainCommand(command: .getDuressSettings)
        guard case let .duressSettingsOpt(settings) = result else {
            throw MobileError.Other(
                detail: "GetDuressSettings: unexpected result variant"
            )
        }
        return settings
    }

    // MARK: - Shred — read-only (C6)

    //
    // The 4 keychain-bound shred operations (panicShred, softShred,
    // hardShred, cancelShred) remain on legacy `vauchi.X` until
    // `MobilePlatformKeychain` plumbing lands on `PlatformAppEngine`
    // (tracked as a separate B7 keychain batch). Only `shredStatus` —
    // a read-only deletion-state snapshot — has a dispatch arm today.

    func shredStatus() throws -> MobileShredStatus {
        let result = try dispatchDomainCommand(command: .shredStatus)
        guard case let .shredStatus(status) = result else {
            throw MobileError.Other(
                detail: "ShredStatus: unexpected result variant"
            )
        }
        return status
    }

    // MARK: - GDPR / Identity Deletion (C6)

    func exportGdprData() throws -> MobileGdprExport {
        let result = try dispatchDomainCommand(command: .exportGdprData)
        guard case let .gdprExport(export) = result else {
            throw MobileError.Other(
                detail: "ExportGdprData: unexpected result variant"
            )
        }
        return export
    }

    func scheduleIdentityDeletion() throws -> MobileDeletionInfo {
        let result = try dispatchDomainCommand(command: .scheduleIdentityDeletion)
        guard case let .deletionInfo(info) = result else {
            throw MobileError.Other(
                detail: "ScheduleIdentityDeletion: unexpected result variant"
            )
        }
        return info
    }

    func cancelIdentityDeletion() throws {
        _ = try dispatchDomainCommand(command: .cancelIdentityDeletion)
    }

    func getDeletionState() throws -> MobileDeletionInfo {
        let result = try dispatchDomainCommand(command: .getDeletionState)
        guard case let .deletionInfo(info) = result else {
            throw MobileError.Other(
                detail: "GetDeletionState: unexpected result variant"
            )
        }
        return info
    }

    // MARK: - Consent (C6)

    func grantConsent(consentType: MobileConsentType) throws {
        _ = try dispatchDomainCommand(command: .grantConsent(consentType: consentType))
    }

    func revokeConsent(consentType: MobileConsentType) throws {
        _ = try dispatchDomainCommand(command: .revokeConsent(consentType: consentType))
    }

    func checkConsent(consentType: MobileConsentType) throws -> Bool {
        let result = try dispatchDomainCommand(command: .checkConsent(consentType: consentType))
        guard case let .bool(value) = result else {
            throw MobileError.Other(
                detail: "CheckConsent: unexpected result variant"
            )
        }
        return value
    }

    func getConsentStatus(consentType: MobileConsentType) throws -> MobileConsentStatus {
        let result = try dispatchDomainCommand(
            command: .getConsentStatus(consentType: consentType)
        )
        guard case let .consentStatus(status) = result else {
            throw MobileError.Other(
                detail: "GetConsentStatus: unexpected result variant"
            )
        }
        return status
    }

    func getConsentRecords() throws -> [MobileConsentRecord] {
        let result = try dispatchDomainCommand(command: .getConsentRecords)
        guard case let .consentRecords(records) = result else {
            throw MobileError.Other(
                detail: "GetConsentRecords: unexpected result variant"
            )
        }
        return records
    }

    // MARK: - Recovery Trust (slice 32g-B Phase 1)

    // Core 0.51.2 retired `vauchi.trustContactForRecovery(id:)` /
    // `untrustContactForRecovery(id:)` / `trustedContactCount()` direct
    // methods on `VauchiPlatform` (and the matching direct methods on
    // `PlatformAppEngine`). All three move to typed `DomainCommand`
    // dispatch. Wrappers match the previous call shapes so
    // `VauchiRepository` migrates with a `vauchi.X()` → `appEngine.X()`
    // swap.

    func trustContactForRecovery(id: String) throws {
        _ = try dispatchDomainCommand(command: .trustContactForRecovery(contactId: id))
    }

    func untrustContactForRecovery(id: String) throws {
        _ = try dispatchDomainCommand(command: .untrustContactForRecovery(contactId: id))
    }

    func trustedContactCount() throws -> UInt32 {
        let result = try dispatchDomainCommand(command: .trustedContactCount)
        guard case let .count(value) = result else {
            throw MobileError.Other(
                detail: "TrustedContactCount: unexpected result variant"
            )
        }
        return value
    }

    // MARK: - Hidden Contacts (slice 32g-B Phase 2)

    func listHiddenContacts() throws -> [MobileContact] {
        let result = try dispatchDomainCommand(command: .listHiddenContacts)
        guard case let .contacts(contacts) = result else {
            throw MobileError.Other(
                detail: "ListHiddenContacts: unexpected result variant"
            )
        }
        return contacts
    }

    // MARK: - Contact Detail Read (slice 32g-B Phase 2)

    func contactDetailFooterActionId(contactId: String) throws -> String {
        let result = try dispatchDomainCommand(
            command: .contactDetailFooterActionId(contactId: contactId)
        )
        guard case let .text(value) = result else {
            throw MobileError.Other(
                detail: "ContactDetailFooterActionId: unexpected result variant"
            )
        }
        return value
    }
}
