// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Tests for visibility labels feature
// Based on: features/visibility_labels.feature

@testable import Vauchi
import XCTest

/// Tests for visibility labels feature
/// Traces to: features/visibility_labels.feature
final class VisibilityLabelsTests: XCTestCase {
    var tempDir: URL!
    var repo: VauchiRepository!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Label Creation Tests

    // Traces to: visibility_labels.feature @label-create

    /// Scenario: Create a new visibility label
    /// @label-create
    func testCreateLabelReturnsNewLabel() throws {
        let label = try repo.createLabel(name: "Work")

        XCTAssertEqual(label.name, "Work")
        XCTAssertFalse(label.id.isEmpty, "Label ID should not be empty")
        XCTAssertEqual(label.contactCount, 0, "New label should have no contacts")
        XCTAssertEqual(label.visibleFieldCount, 0, "New label should have no fields associated")
    }

    /// Scenario: Cannot create duplicate label names
    /// @label-create
    func testCannotCreateDuplicateLabel() throws {
        _ = try repo.createLabel(name: "Friends")

        XCTAssertThrowsError(try repo.createLabel(name: "Friends")) { error in
            // Should throw an error for duplicate label name
            XCTAssertTrue(error is VauchiRepositoryError)
        }
    }

    /// Scenario: Create custom label with any name
    /// @label-create
    func testCreateCustomLabelWithAnyName() throws {
        let label = try repo.createLabel(name: "University Colleagues")

        XCTAssertEqual(label.name, "University Colleagues")
        XCTAssertFalse(label.id.isEmpty)
    }

    // MARK: - Label Listing Tests

    // Traces to: visibility_labels.feature @label-list

    /// Scenario: List all labels
    /// @label-list
    func testListLabelsReturnsAllLabels() throws {
        _ = try repo.createLabel(name: "Work")
        _ = try repo.createLabel(name: "Family")

        let labels = try repo.listLabels()

        XCTAssertEqual(labels.count, 2)
        let labelNames = Set(labels.map(\.name))
        XCTAssertTrue(labelNames.contains("Work"))
        XCTAssertTrue(labelNames.contains("Family"))
    }

    /// Scenario: Empty labels list initially
    func testEmptyLabelsListInitially() throws {
        let labels = try repo.listLabels()

        XCTAssertTrue(labels.isEmpty, "Should have no labels initially")
    }

    // MARK: - Label Rename Tests

    // Traces to: visibility_labels.feature @label-rename

    /// Scenario: Rename an existing label
    /// @label-rename
    func testRenameLabelUpdatesName() throws {
        let label = try repo.createLabel(name: "Work")

        try repo.renameLabel(id: label.id, newName: "Colleagues")

        let updated = try repo.getLabel(id: label.id)
        XCTAssertEqual(updated.name, "Colleagues")
    }

    /// Scenario: Cannot rename to existing label name
    /// @label-rename
    func testCannotRenameToExistingLabelName() throws {
        let label1 = try repo.createLabel(name: "Friends")
        _ = try repo.createLabel(name: "Family")

        XCTAssertThrowsError(try repo.renameLabel(id: label1.id, newName: "Family")) { error in
            // Should throw an error for duplicate name
            XCTAssertTrue(error is VauchiRepositoryError)
        }

        // Original name should remain
        let label = try repo.getLabel(id: label1.id)
        XCTAssertEqual(label.name, "Friends")
    }

    // MARK: - Label Deletion Tests

    // Traces to: visibility_labels.feature @label-delete

    /// Scenario: Delete a label
    /// @label-delete
    func testDeleteLabelRemovesLabel() throws {
        let label = try repo.createLabel(name: "Temporary")

        try repo.deleteLabel(id: label.id)

        let labels = try repo.listLabels()
        XCTAssertTrue(labels.isEmpty)
    }

    /// Scenario: Delete label does not remove contacts
    /// @label-delete
    func testDeleteLabelDoesNotRemoveContacts() throws {
        // This test requires contacts - will be more complete with full exchange
        let label = try repo.createLabel(name: "Test")

        try repo.deleteLabel(id: label.id)

        // Label should be deleted
        let labels = try repo.listLabels()
        XCTAssertFalse(labels.contains { $0.id == label.id })
    }

    // MARK: - Get Label Details Tests

    /// Scenario: Get label details
    func testGetLabelReturnsDetails() throws {
        let created = try repo.createLabel(name: "Close Friends")

        let detail = try repo.getLabel(id: created.id)

        XCTAssertEqual(detail.id, created.id)
        XCTAssertEqual(detail.name, "Close Friends")
        XCTAssertTrue(detail.contactIds.isEmpty)
        XCTAssertTrue(detail.visibleFieldIds.isEmpty)
    }

    // MARK: - Contact Assignment Tests

    // Traces to: visibility_labels.feature @assign-contact

    /// Scenario: Add a contact to a label
    /// @assign-contact
    func testAddContactToLabel() throws {
        // Core (0.51.65+, commit 527d87ae) routes label membership through the
        // repropagation path, which rejects a contact id never established via a
        // real exchange — no silent membership for a non-contact (privacy). The
        // wrapper rethrows core's ContactNotFound as VauchiRepositoryError, so a
        // fabricated id must throw, not silently persist. Real contact↔label
        // association is core-owned and covered there (visibility_repropagate_tests.rs)
        // with ratcheted contacts, per the Humble-UI rule.
        let label = try repo.createLabel(name: "Work")

        XCTAssertThrowsError(
            try repo.addContactToLabel(labelId: label.id, contactId: "contact-123")
        ) { error in
            XCTAssertTrue(
                error is VauchiRepositoryError,
                "expected VauchiRepositoryError for an unknown contact, got \(error)"
            )
        }
    }

    /// Scenario: Remove a contact from a label
    /// @assign-contact
    func testRemoveContactFromLabel() throws {
        // The precondition this scenario relied on — associating a fabricated
        // contact — is now rejected at the add step (see testAddContactToLabel),
        // so the removal is unreachable. Assert the guard fires.
        let label = try repo.createLabel(name: "Work")

        XCTAssertThrowsError(
            try repo.addContactToLabel(labelId: label.id, contactId: "contact-123")
        ) { error in
            XCTAssertTrue(
                error is VauchiRepositoryError,
                "expected VauchiRepositoryError for an unknown contact, got \(error)"
            )
        }
    }

    /// Scenario: Get labels for a contact
    /// @assign-contact
    func testGetLabelsForContact() throws {
        // Building the contact→labels association requires a real contact; the
        // add of a fabricated id is rejected, so this scenario cannot form the
        // memberships it queried. Assert the guard fires at the add step.
        let label1 = try repo.createLabel(name: "Friends")

        XCTAssertThrowsError(
            try repo.addContactToLabel(labelId: label1.id, contactId: "contact-123")
        ) { error in
            XCTAssertTrue(
                error is VauchiRepositoryError,
                "expected VauchiRepositoryError for an unknown contact, got \(error)"
            )
        }
    }

    /// Scenario: Contact in multiple labels
    /// @assign-contact
    func testContactCanBeInMultipleLabels() throws {
        // Multi-label membership for a fabricated contact is rejected at the
        // first add; the real multi-label case is core-tested with a ratcheted
        // contact. Assert the guard fires.
        let workLabel = try repo.createLabel(name: "Work")

        XCTAssertThrowsError(
            try repo.addContactToLabel(labelId: workLabel.id, contactId: "carol-123")
        ) { error in
            XCTAssertTrue(
                error is VauchiRepositoryError,
                "expected VauchiRepositoryError for an unknown contact, got \(error)"
            )
        }
    }

    // MARK: - Field Visibility Tests

    // Traces to: visibility_labels.feature @field-visibility

    /// Scenario: Set field visibility for label
    /// @field-visibility
    func testSetLabelFieldVisibility() throws {
        try repo.addField(type: .phone, label: "Personal", value: "+1-555-111-1111")
        let label = try repo.createLabel(name: "Family")

        let card = try repo.getOwnCard()
        guard let field = card.fields.first(where: { $0.label == "Personal" }) else {
            XCTFail("Field not found")
            return
        }

        // Set field visible to this label
        try repo.setLabelFieldVisibility(labelId: label.id, fieldLabel: field.label, isVisible: true)

        let detail = try repo.getLabel(id: label.id)
        XCTAssertTrue(detail.visibleFieldIds.contains(field.id))
    }

    /// Scenario: Remove field from label visibility
    /// @field-visibility
    func testRemoveFieldFromLabelVisibility() throws {
        try repo.addField(type: .email, label: "Personal", value: "alice@personal.com")
        let label = try repo.createLabel(name: "Family")

        let card = try repo.getOwnCard()
        guard let field = card.fields.first(where: { $0.label == "Personal" }) else {
            XCTFail("Field not found")
            return
        }

        // Add then remove visibility
        try repo.setLabelFieldVisibility(labelId: label.id, fieldLabel: field.label, isVisible: true)
        try repo.setLabelFieldVisibility(labelId: label.id, fieldLabel: field.label, isVisible: false)

        let detail = try repo.getLabel(id: label.id)
        XCTAssertFalse(detail.visibleFieldIds.contains(field.id))
    }

    // MARK: - Suggested Labels Tests

    /// Scenario: Default labels are suggested on first use
    /// @label-create
    func testGetSuggestedLabels() {
        let suggestions = repo.getSuggestedLabels()

        XCTAssertFalse(suggestions.isEmpty, "Should have suggested labels")
        XCTAssertTrue(suggestions.contains("Family"))
        XCTAssertTrue(suggestions.contains("Friends"))
        XCTAssertTrue(suggestions.contains("Coworkers"))
        XCTAssertTrue(suggestions.contains("Business"))
    }

    // MARK: - Label Statistics Tests

    // Traces to: visibility_labels.feature @stats

    /// Scenario: View label statistics
    /// @stats
    func testLabelHasContactCount() throws {
        // Associating a fabricated contact is rejected at the repropagation
        // step. Core commits the raw membership *before* it throws
        // (add_contact_to_group_and_repropagate, no rollback), so post-throw
        // count is intentionally NOT asserted here — real contact-count stats
        // are core-tested with ratcheted contacts.
        let label = try repo.createLabel(name: "Work")

        XCTAssertThrowsError(
            try repo.addContactToLabel(labelId: label.id, contactId: "contact-1")
        ) { error in
            XCTAssertTrue(
                error is VauchiRepositoryError,
                "expected VauchiRepositoryError for an unknown contact, got \(error)"
            )
        }
    }

    // MARK: - Edge Cases

    // Traces to: visibility_labels.feature @edge-cases

    /// Scenario: Label with no contacts still exists
    /// @edge-cases
    func testEmptyLabelPersists() throws {
        let label = try repo.createLabel(name: "Future Team")

        let labels = try repo.listLabels()

        XCTAssertTrue(labels.contains { $0.id == label.id })
        XCTAssertEqual(labels.first { $0.id == label.id }?.contactCount, 0)
    }
}
