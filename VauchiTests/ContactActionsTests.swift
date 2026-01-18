// ContactActionsTests.swift
// Tests for ContactActions service
// Based on: features/contact_card_management.feature - field action requirements

import XCTest
@testable import Vauchi

final class ContactActionsTests: XCTestCase {

    // MARK: - Field Type Detection Tests

    /// Scenario: Detect phone field type
    func testDetectPhoneFieldType() {
        XCTAssertEqual(ContactActions.detectFieldType("+1234567890"), .phone)
        XCTAssertEqual(ContactActions.detectFieldType("(555) 123-4567"), .phone)
        XCTAssertEqual(ContactActions.detectFieldType("+44 20 7123 4567"), .phone)
    }

    /// Scenario: Detect email field type
    func testDetectEmailFieldType() {
        XCTAssertEqual(ContactActions.detectFieldType("alice@example.com"), .email)
        XCTAssertEqual(ContactActions.detectFieldType("user.name+tag@example.org"), .email)
    }

    /// Scenario: Detect website field type
    func testDetectWebsiteFieldType() {
        XCTAssertEqual(ContactActions.detectFieldType("https://example.com"), .website)
        XCTAssertEqual(ContactActions.detectFieldType("http://example.com/path"), .website)
        XCTAssertEqual(ContactActions.detectFieldType("www.example.com"), .website)
    }

    /// Scenario: Custom field type for unrecognized values
    func testDetectCustomFieldType() {
        XCTAssertEqual(ContactActions.detectFieldType("just some text"), .custom)
        XCTAssertEqual(ContactActions.detectFieldType("1234"), .custom)
    }

    // MARK: - URL Generation Tests

    /// Scenario: Generate phone URL
    func testBuildPhoneUrl() {
        let url = ContactActions.buildUrl(for: "+1234567890", type: .phone)
        XCTAssertEqual(url?.scheme, "tel")
    }

    /// Scenario: Generate SMS URL
    func testBuildSmsUrl() {
        let url = ContactActions.buildSmsUrl(for: "+1234567890")
        XCTAssertEqual(url?.scheme, "sms")
    }

    /// Scenario: Generate email URL
    func testBuildEmailUrl() {
        let url = ContactActions.buildUrl(for: "alice@example.com", type: .email)
        XCTAssertEqual(url?.scheme, "mailto")
    }

    /// Scenario: Generate website URL
    func testBuildWebsiteUrl() {
        let url = ContactActions.buildUrl(for: "https://example.com", type: .website)
        XCTAssertEqual(url?.scheme, "https")
    }

    /// Scenario: Generate website URL without scheme
    func testBuildWebsiteUrlWithoutScheme() {
        let url = ContactActions.buildUrl(for: "example.com", type: .website)
        XCTAssertEqual(url?.scheme, "https")
    }

    /// Scenario: Generate maps URL for address
    func testBuildAddressUrl() {
        let url = ContactActions.buildUrl(for: "123 Main St", type: .address)
        XCTAssertNotNil(url)
        // Should be Apple Maps URL or fallback
    }

    // MARK: - Security Tests

    /// Scenario: Block dangerous URL schemes
    func testBlockDangerousSchemes() {
        XCTAssertFalse(ContactActions.isSafeUrl("javascript:alert('xss')"))
        XCTAssertFalse(ContactActions.isSafeUrl("vbscript:msgbox('xss')"))
        XCTAssertFalse(ContactActions.isSafeUrl("data:text/html,<script>"))
        XCTAssertFalse(ContactActions.isSafeUrl("file:///etc/passwd"))
    }

    /// Scenario: Allow safe URL schemes
    func testAllowSafeSchemes() {
        XCTAssertTrue(ContactActions.isSafeUrl("https://example.com"))
        XCTAssertTrue(ContactActions.isSafeUrl("http://example.com"))
        XCTAssertTrue(ContactActions.isSafeUrl("tel:+1234567890"))
        XCTAssertTrue(ContactActions.isSafeUrl("mailto:user@example.com"))
        XCTAssertTrue(ContactActions.isSafeUrl("sms:+1234567890"))
    }

    // MARK: - Social Network URL Tests

    /// Scenario: Build GitHub profile URL
    func testBuildGitHubUrl() {
        let url = ContactActions.buildSocialUrl(network: "github", username: "octocat")
        XCTAssertEqual(url?.absoluteString, "https://github.com/octocat")
    }

    /// Scenario: Build Twitter profile URL
    func testBuildTwitterUrl() {
        let url = ContactActions.buildSocialUrl(network: "twitter", username: "jack")
        XCTAssertEqual(url?.absoluteString, "https://twitter.com/jack")
    }

    /// Scenario: Build LinkedIn profile URL
    func testBuildLinkedInUrl() {
        let url = ContactActions.buildSocialUrl(network: "linkedin", username: "johndoe")
        XCTAssertEqual(url?.absoluteString, "https://linkedin.com/in/johndoe")
    }

    // MARK: - Action Types Tests

    /// Scenario: Get available actions for phone field
    func testAvailableActionsForPhone() {
        let actions = ContactActions.availableActions(for: .phone)
        XCTAssertTrue(actions.contains(.call))
        XCTAssertTrue(actions.contains(.sms))
        XCTAssertTrue(actions.contains(.copy))
    }

    /// Scenario: Get available actions for email field
    func testAvailableActionsForEmail() {
        let actions = ContactActions.availableActions(for: .email)
        XCTAssertTrue(actions.contains(.email))
        XCTAssertTrue(actions.contains(.copy))
    }

    /// Scenario: Get available actions for website field
    func testAvailableActionsForWebsite() {
        let actions = ContactActions.availableActions(for: .website)
        XCTAssertTrue(actions.contains(.openUrl))
        XCTAssertTrue(actions.contains(.copy))
    }
}
