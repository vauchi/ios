// VisibilityLabelsTests.swift
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
        // Create temp directory for each test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
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
        let labelNames = Set(labels.map { $0.name })
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
        let label = try repo.createLabel(name: "Work")
        let contactId = "contact-123" // Simulated contact ID

        try repo.addContactToLabel(labelId: label.id, contactId: contactId)

        let detail = try repo.getLabel(id: label.id)
        XCTAssertTrue(detail.contactIds.contains(contactId))
    }

    /// Scenario: Remove a contact from a label
    /// @assign-contact
    func testRemoveContactFromLabel() throws {
        let label = try repo.createLabel(name: "Work")
        let contactId = "contact-123"
        try repo.addContactToLabel(labelId: label.id, contactId: contactId)

        try repo.removeContactFromLabel(labelId: label.id, contactId: contactId)

        let detail = try repo.getLabel(id: label.id)
        XCTAssertFalse(detail.contactIds.contains(contactId))
    }

    /// Scenario: Get labels for a contact
    /// @assign-contact
    func testGetLabelsForContact() throws {
        let label1 = try repo.createLabel(name: "Friends")
        let label2 = try repo.createLabel(name: "Colleagues")
        let contactId = "contact-123"

        try repo.addContactToLabel(labelId: label1.id, contactId: contactId)
        try repo.addContactToLabel(labelId: label2.id, contactId: contactId)

        let contactLabels = try repo.getLabelsForContact(contactId: contactId)

        XCTAssertEqual(contactLabels.count, 2)
        let labelIds = Set(contactLabels.map { $0.id })
        XCTAssertTrue(labelIds.contains(label1.id))
        XCTAssertTrue(labelIds.contains(label2.id))
    }

    /// Scenario: Contact in multiple labels
    /// @assign-contact
    func testContactCanBeInMultipleLabels() throws {
        let workLabel = try repo.createLabel(name: "Work")
        let friendsLabel = try repo.createLabel(name: "Friends")
        let contactId = "carol-123"

        try repo.addContactToLabel(labelId: workLabel.id, contactId: contactId)
        try repo.addContactToLabel(labelId: friendsLabel.id, contactId: contactId)

        let workDetail = try repo.getLabel(id: workLabel.id)
        let friendsDetail = try repo.getLabel(id: friendsLabel.id)

        XCTAssertTrue(workDetail.contactIds.contains(contactId))
        XCTAssertTrue(friendsDetail.contactIds.contains(contactId))
    }

    // MARK: - Field Visibility Tests

    // Traces to: visibility_labels.feature @field-visibility

    /// Scenario: Set field visibility for label
    /// @field-visibility
    func testSetLabelFieldVisibility() throws {
        // Add a field first
        try repo.addField(type: .phone, label: "Personal", value: "+1-555-111-1111")
        let label = try repo.createLabel(name: "Family")

        // Get the field ID from the card
        let card = try repo.getOwnCard()
        guard let field = card.fields.first(where: { $0.label == "Personal" }) else {
            XCTFail("Field not found")
            return
        }

        // Set field visible to this label
        try repo.setLabelFieldVisibility(labelId: label.id, fieldId: field.id, visible: true)

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
        try repo.setLabelFieldVisibility(labelId: label.id, fieldId: field.id, visible: true)
        try repo.setLabelFieldVisibility(labelId: label.id, fieldId: field.id, visible: false)

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
        XCTAssertTrue(suggestions.contains("Professional"))
    }

    // MARK: - Label Statistics Tests

    // Traces to: visibility_labels.feature @stats

    /// Scenario: View label statistics
    /// @stats
    func testLabelHasContactCount() throws {
        let label = try repo.createLabel(name: "Work")
        let contactIds = ["contact-1", "contact-2", "contact-3"]

        for id in contactIds {
            try repo.addContactToLabel(labelId: label.id, contactId: id)
        }

        let labels = try repo.listLabels()
        let workLabel = labels.first { $0.name == "Work" }

        XCTAssertNotNil(workLabel)
        XCTAssertEqual(workLabel?.contactCount, 3)
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
