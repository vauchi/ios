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

    // MARK: - Content Updates

    /// Run the whole content-update cycle (check → apply → screen
    /// invalidation) in core and return its presentation-only outcome
    /// (core 0.51.69, `RunContentUpdateCycle`).
    func runContentUpdateCycle() throws -> MobileContentCycleOutcome {
        let result = try dispatchDomainCommand(command: .runContentUpdateCycle)
        guard case let .contentUpdateCycle(outcome) = result else {
            throw MobileError.Other(
                detail: "RunContentUpdateCycle: unexpected result variant"
            )
        }
        return outcome
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

    // MARK: - Decoy Contacts (B7 batch 7)

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

    // MARK: - Contact Verification (C2)

    // MARK: - Contact Notes (C2)

    // MARK: - Field Visibility (C3)

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

    // MARK: - Certificate Pinning (C8 partial)

    // MARK: - Passcode (C6)

    func authenticate(password: String) throws -> MobileAuthMode {
        let result = try dispatchDomainCommand(command: .authenticate(password: password))
        guard case let .authMode(mode) = result else {
            throw MobileError.Other(
                detail: "Authenticate: unexpected result variant"
            )
        }
        return mode
    }

    // MARK: - Duress (C6)

    // MARK: - Shred — read-only (C6)

    // MARK: - Hidden Contacts (slice 32g-B Phase 2)

    // MARK: - Contact Detail Read (slice 32g-B Phase 2)
}
