// VauchiRepositoryTests.swift
// Tests for VauchiRepository - based on features/*.feature Gherkin scenarios

import XCTest
@testable import Vauchi

/// Tests for VauchiRepository
/// Based on: features/identity_management.feature, features/contact_card_management.feature
final class VauchiRepositoryTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        // Create temp directory for each test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Identity Management Tests
    // Based on: features/identity_management.feature

    /// Scenario: First launch - no identity exists
    func testNoIdentityOnFirstLaunch() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        XCTAssertFalse(repo.hasIdentity(), "Should have no identity on first launch")
    }

    /// Scenario: Create new identity with display name
    func testCreateIdentity() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        XCTAssertFalse(repo.hasIdentity())

        try repo.createIdentity(displayName: "Alice")

        XCTAssertTrue(repo.hasIdentity(), "Should have identity after creation")
        XCTAssertEqual(try repo.getDisplayName(), "Alice")
    }

    /// Scenario: Identity generates Ed25519 keypair
    func testIdentityHasPublicId() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let publicId = try repo.getPublicId()

        XCTAssertFalse(publicId.isEmpty, "Public ID should not be empty")
        // Ed25519 public key is 32 bytes = 64 hex chars
        XCTAssertEqual(publicId.count, 64, "Public ID should be 64 hex characters")
    }

    /// Scenario: Identity persists across sessions
    func testIdentityPersistsAcrossSessions() throws {
        // First session - create identity
        do {
            let repo = try VauchiRepository(dataDir: tempDir.path)
            try repo.createIdentity(displayName: "Alice")
        }

        // Second session - identity should exist
        let repo2 = try VauchiRepository(dataDir: tempDir.path)
        XCTAssertTrue(repo2.hasIdentity(), "Identity should persist across sessions")
        XCTAssertEqual(try repo2.getDisplayName(), "Alice")
    }

    /// Scenario: Cannot create identity twice
    func testCannotCreateIdentityTwice() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        XCTAssertThrowsError(try repo.createIdentity(displayName: "Bob")) { error in
            guard case VauchiRepositoryError.alreadyInitialized = error else {
                XCTFail("Expected alreadyInitialized error, got \(error)")
                return
            }
        }
    }

    // MARK: - Contact Card Tests
    // Based on: features/contact_card_management.feature

    /// Scenario: Initial card has display name only
    func testInitialCardHasDisplayName() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let card = try repo.getOwnCard()

        XCTAssertEqual(card.displayName, "Alice")
        XCTAssertTrue(card.fields.isEmpty, "Initial card should have no fields")
    }

    /// Scenario: Add email field to card
    func testAddEmailField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        try repo.addField(type: .email, label: "Work", value: "alice@company.com")

        let card = try repo.getOwnCard()
        XCTAssertEqual(card.fields.count, 1)
        XCTAssertEqual(card.fields[0].fieldType, .email)
        XCTAssertEqual(card.fields[0].label, "Work")
        XCTAssertEqual(card.fields[0].value, "alice@company.com")
    }

    /// Scenario: Add phone field to card
    func testAddPhoneField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        try repo.addField(type: .phone, label: "Mobile", value: "+1234567890")

        let card = try repo.getOwnCard()
        XCTAssertEqual(card.fields.count, 1)
        XCTAssertEqual(card.fields[0].fieldType, .phone)
        XCTAssertEqual(card.fields[0].label, "Mobile")
        XCTAssertEqual(card.fields[0].value, "+1234567890")
    }

    /// Scenario: Update field value
    func testUpdateFieldValue() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
        try repo.addField(type: .phone, label: "Mobile", value: "+1234567890")

        try repo.updateField(label: "Mobile", newValue: "+0987654321")

        let card = try repo.getOwnCard()
        XCTAssertEqual(card.fields[0].value, "+0987654321")
    }

    /// Scenario: Remove field from card
    func testRemoveField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
        try repo.addField(type: .email, label: "Work", value: "alice@company.com")

        let removed = try repo.removeField(label: "Work")

        XCTAssertTrue(removed, "removeField should return true")
        let card = try repo.getOwnCard()
        XCTAssertTrue(card.fields.isEmpty, "Field should be removed")
    }

    /// Scenario: Remove non-existent field returns false
    func testRemoveNonExistentField() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let removed = try repo.removeField(label: "NonExistent")

        XCTAssertFalse(removed, "Removing non-existent field should return false")
    }

    /// Scenario: Update display name
    func testUpdateDisplayName() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        try repo.setDisplayName("Alice Smith")

        XCTAssertEqual(try repo.getDisplayName(), "Alice Smith")
        let card = try repo.getOwnCard()
        XCTAssertEqual(card.displayName, "Alice Smith")
    }

    // MARK: - Contact Exchange Tests
    // Based on: features/contact_exchange.feature

    /// Scenario: Generate exchange QR code
    func testGenerateExchangeQr() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let exchangeData = try repo.generateExchangeQr()

        XCTAssertTrue(exchangeData.qrData.hasPrefix("wb://"), "QR data should start with wb://")
        XCTAssertFalse(exchangeData.publicId.isEmpty)
        XCTAssertGreaterThan(exchangeData.expiresAt, UInt64(Date().timeIntervalSince1970))
    }

    /// Scenario: QR code expires after 5 minutes
    func testQrCodeExpiration() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let exchangeData = try repo.generateExchangeQr()
        let now = UInt64(Date().timeIntervalSince1970)

        // Should expire in ~5 minutes (300 seconds)
        let expiresIn = exchangeData.expiresAt - now
        XCTAssertGreaterThanOrEqual(expiresIn, 295, "Should expire in at least 295 seconds")
        XCTAssertLessThanOrEqual(expiresIn, 305, "Should expire in at most 305 seconds")
    }

    // MARK: - Contact Management Tests
    // Based on: features/contacts_management.feature

    /// Scenario: Empty contacts list on first launch
    func testEmptyContactsList() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let contacts = try repo.listContacts()

        XCTAssertTrue(contacts.isEmpty, "Contact list should be empty initially")
        XCTAssertEqual(try repo.contactCount(), 0)
    }

    /// Scenario: Search contacts returns empty for no matches
    func testSearchContactsEmpty() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let results = try repo.searchContacts(query: "Bob")

        XCTAssertTrue(results.isEmpty, "Search should return empty for no matches")
    }

    /// Scenario: Get non-existent contact returns nil
    func testGetNonExistentContact() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let contact = try repo.getContact(id: "nonexistent")

        XCTAssertNil(contact, "Non-existent contact should return nil")
    }

    // MARK: - Backup Tests
    // Based on: features/identity_management.feature

    /// Scenario: Export encrypted backup
    func testExportBackup() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")
        try repo.addField(type: .email, label: "Work", value: "alice@company.com")

        let backup = try repo.exportBackup(password: "correct-horse-battery-staple")

        XCTAssertFalse(backup.isEmpty, "Backup should not be empty")
        // Backup is base64 encoded
        XCTAssertNotNil(Data(base64Encoded: backup), "Backup should be valid base64")
    }

    /// Scenario: Import backup restores identity
    func testImportBackup() throws {
        var backupData: String!

        // Create identity and export backup
        do {
            let repo = try VauchiRepository(dataDir: tempDir.path)
            try repo.createIdentity(displayName: "Alice")
            try repo.addField(type: .email, label: "Work", value: "alice@company.com")
            backupData = try repo.exportBackup(password: "password123")
        }

        // Create new repository and import backup
        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: newDir) }

        let repo2 = try VauchiRepository(dataDir: newDir.path)
        try repo2.importBackup(data: backupData, password: "password123")

        XCTAssertTrue(repo2.hasIdentity())
        XCTAssertEqual(try repo2.getDisplayName(), "Alice")
    }

    // MARK: - Sync Tests
    // Based on: features/sync_updates.feature

    /// Scenario: Initial sync status is idle
    func testInitialSyncStatusIsIdle() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        XCTAssertEqual(repo.getSyncStatus(), .idle)
    }

    /// Scenario: Initial pending update count is zero
    func testInitialPendingUpdateCount() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let count = try repo.pendingUpdateCount()

        XCTAssertEqual(count, 0)
    }

    // MARK: - Social Networks Tests

    /// Scenario: List available social networks
    func testListSocialNetworks() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        let networks = repo.listSocialNetworks()

        XCTAssertFalse(networks.isEmpty, "Should have default social networks")
    }

    /// Scenario: Get profile URL for social network
    func testGetProfileUrl() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)

        let url = repo.getProfileUrl(networkId: "github", username: "octocat")

        XCTAssertEqual(url, "https://github.com/octocat")
    }

    // MARK: - Recovery Tests
    // Based on: features/contact_recovery.feature

    /// Scenario: Create new identity after device loss
    /// Alice can initiate recovery claiming "pk_old"
    func testCreateRecoveryClaim() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        // Simulate old public key (64 hex chars = 32 bytes Ed25519 key)
        let oldPkHex = String(repeating: "a", count: 64)

        let claim = try repo.createRecoveryClaim(oldPkHex: oldPkHex)

        XCTAssertEqual(claim.oldPublicKey, oldPkHex)
        XCTAssertEqual(claim.newPublicKey, try repo.getPublicId())
        XCTAssertFalse(claim.claimData.isEmpty, "Claim data should not be empty")
        XCTAssertFalse(claim.isExpired, "Fresh claim should not be expired")
    }

    /// Scenario: Generate recovery claim QR code
    /// The QR code contains old_pk, new_pk, and timestamp
    func testRecoveryClaimContainsRequiredFields() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "b", count: 64)
        let claim = try repo.createRecoveryClaim(oldPkHex: oldPkHex)

        // Claim data should be base64 encoded
        XCTAssertNotNil(Data(base64Encoded: claim.claimData), "Claim should be valid base64")
        XCTAssertEqual(claim.oldPublicKey.count, 64, "Old public key should be 64 hex chars")
        XCTAssertEqual(claim.newPublicKey.count, 64, "New public key should be 64 hex chars")
    }

    /// Scenario: Parse recovery claim from base64
    func testParseRecoveryClaim() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "c", count: 64)
        let claim = try repo.createRecoveryClaim(oldPkHex: oldPkHex)

        // Parse the claim back
        let parsed = try repo.parseRecoveryClaim(claimB64: claim.claimData)

        XCTAssertEqual(parsed.oldPublicKey, oldPkHex)
        XCTAssertEqual(parsed.newPublicKey, claim.newPublicKey)
    }

    /// Scenario: Get recovery status when no active recovery
    func testNoActiveRecoveryStatus() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let status = try repo.getRecoveryStatus()

        XCTAssertNil(status, "Should have no active recovery initially")
    }

    /// Scenario: Get recovery status after creating claim
    func testRecoveryStatusAfterClaimCreation() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "d", count: 64)
        _ = try repo.createRecoveryClaim(oldPkHex: oldPkHex)

        let status = try repo.getRecoveryStatus()

        XCTAssertNotNil(status, "Should have active recovery after claim creation")
        XCTAssertEqual(status?.oldPublicKey, oldPkHex)
        XCTAssertEqual(status?.vouchersCollected, 0)
        XCTAssertGreaterThan(status?.vouchersNeeded ?? 0, 0, "Should need at least 1 voucher")
        XCTAssertFalse(status?.isComplete ?? true)
    }

    /// Scenario: Default recovery threshold
    /// The default recovery threshold should be 3 vouchers
    func testDefaultRecoveryThreshold() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "e", count: 64)
        _ = try repo.createRecoveryClaim(oldPkHex: oldPkHex)

        let status = try repo.getRecoveryStatus()

        XCTAssertEqual(status?.vouchersNeeded, 3, "Default threshold should be 3 vouchers")
    }

    /// Scenario: Get recovery proof when incomplete
    func testNoRecoveryProofWhenIncomplete() throws {
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "f", count: 64)
        _ = try repo.createRecoveryClaim(oldPkHex: oldPkHex)

        let proof = try repo.getRecoveryProof()

        XCTAssertNil(proof, "Should not have proof when recovery incomplete")
    }

    /// Scenario: Create voucher for someone's recovery claim
    /// Tests the full flow: Alice creates claim, Bob creates voucher
    func testCreateVoucherForClaim() throws {
        // Alice creates a claim on her new device
        let aliceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliceDir) }

        let aliceRepo = try VauchiRepository(dataDir: aliceDir.path)
        try aliceRepo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "1", count: 64)
        let claim = try aliceRepo.createRecoveryClaim(oldPkHex: oldPkHex)

        // Bob has Alice as a contact (simulated by having an identity)
        let bobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bobDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bobDir) }

        let bobRepo = try VauchiRepository(dataDir: bobDir.path)
        try bobRepo.createIdentity(displayName: "Bob")

        // Bob creates a voucher for Alice's claim
        let voucher = try bobRepo.createRecoveryVoucher(claimB64: claim.claimData)

        XCTAssertFalse(voucher.voucherData.isEmpty, "Voucher data should not be empty")
        XCTAssertEqual(voucher.voucherPublicKey, try bobRepo.getPublicId(), "Voucher should be from Bob")
    }

    /// Scenario: Parse claim and verify details before vouching
    func testParseClaimBeforeVouching() throws {
        // Alice creates a claim
        let aliceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliceDir) }

        let aliceRepo = try VauchiRepository(dataDir: aliceDir.path)
        try aliceRepo.createIdentity(displayName: "Alice")

        let oldPkHex = String(repeating: "2", count: 64)
        let claim = try aliceRepo.createRecoveryClaim(oldPkHex: oldPkHex)

        // Bob parses the claim to verify details
        let bobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bobDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bobDir) }

        let bobRepo = try VauchiRepository(dataDir: bobDir.path)
        try bobRepo.createIdentity(displayName: "Bob")

        let parsedClaim = try bobRepo.parseRecoveryClaim(claimB64: claim.claimData)

        // Bob can see the old and new public keys
        XCTAssertEqual(parsedClaim.oldPublicKey, oldPkHex)
        XCTAssertEqual(parsedClaim.newPublicKey, try aliceRepo.getPublicId())
        XCTAssertFalse(parsedClaim.isExpired)
    }
}
