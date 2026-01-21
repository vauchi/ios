// ContactActions.swift
// Smart field actions for contact fields in Vauchi iOS
// Provides URL building, field type detection, and security validation

import Foundation
import UIKit

/// Service for handling contact field actions (call, email, open URL, etc.)
enum ContactActions {
    // MARK: - Action Types

    /// Available actions for contact fields
    enum Action: String, CaseIterable {
        case call
        case sms
        case email
        case openUrl
        case openMaps
        case copy
    }

    // MARK: - Security
    // URL safety validation: mirrors vauchi-core's is_safe_url()
    // Uses scheme allowlist/blocklist to prevent dangerous URIs

    /// Allowed URI schemes (security whitelist)
    private static let allowedSchemes = ["tel", "mailto", "sms", "https", "http", "geo", "maps"]

    /// Blocked URI schemes (explicit blocklist for dangerous schemes)
    private static let blockedSchemes = ["javascript", "vbscript", "data", "file", "ftp", "blob"]

    // MARK: - Social Network URLs
    // Social network URL generation is now handled by vauchi-core via UniFFI.
    // Use VauchiRepository.getProfileUrl(networkId:username:) to generate profile URLs.
    // The core maintains a comprehensive registry of 40+ social networks.

    // MARK: - Field Type Detection

    /// Detect the type of a field based on its value
    static func detectFieldType(_ value: String) -> VauchiFieldType {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for phone number patterns
        if isPhoneNumber(trimmed) {
            return .phone
        }

        // Check for email
        if isEmail(trimmed) {
            return .email
        }

        // Check for URL/website
        if isWebsite(trimmed) {
            return .website
        }

        return .custom
    }

    private static func isPhoneNumber(_ value: String) -> Bool {
        // Remove common formatting characters
        let cleaned = value.replacingOccurrences(of: "[\\s\\-\\(\\)\\.]", with: "", options: .regularExpression)
        // Check if it starts with + or digits and contains mostly digits
        let phonePattern = "^\\+?[0-9]{7,15}$"
        return cleaned.range(of: phonePattern, options: .regularExpression) != nil
    }

    private static func isEmail(_ value: String) -> Bool {
        let emailPattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return value.range(of: emailPattern, options: .regularExpression) != nil
    }

    private static func isWebsite(_ value: String) -> Bool {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return true
        }
        if value.hasPrefix("www.") {
            return true
        }
        // Check for domain-like pattern
        let domainPattern = "^[a-zA-Z0-9][a-zA-Z0-9-]*\\.[a-zA-Z]{2,}"
        return value.range(of: domainPattern, options: .regularExpression) != nil
    }

    // MARK: - URL Building

    /// Build a URL for the given field value and type
    static func buildUrl(for value: String, type: VauchiFieldType) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case .phone:
            let cleaned = trimmed.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
            return URL(string: "tel:\(cleaned)")

        case .email:
            return URL(string: "mailto:\(trimmed)")

        case .website:
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return URL(string: trimmed)
            }
            return URL(string: "https://\(trimmed)")

        case .address:
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            // Try Apple Maps first, fallback to generic maps: scheme
            return URL(string: "maps://?q=\(encoded)")

        case .social:
            // For social fields, the value might already be a URL
            if trimmed.hasPrefix("http") {
                return URL(string: trimmed)
            }
            return nil

        case .custom:
            // Try to detect and handle custom fields
            let detected = detectFieldType(trimmed)
            if detected != .custom {
                return buildUrl(for: value, type: detected)
            }
            return nil
        }
    }

    /// Build an SMS URL for the given phone number
    static func buildSmsUrl(for phoneNumber: String) -> URL? {
        let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return URL(string: "sms:\(cleaned)")
    }

    /// Build a social network profile URL using vauchi-core registry
    /// Note: Prefer using VauchiRepository.getProfileUrl(networkId:username:) directly
    static func buildSocialUrl(network: String, username: String, repository: VauchiRepository? = nil) -> URL? {
        // Use core's social network registry which has 40+ networks
        if let repo = repository,
           let urlString = repo.getProfileUrl(networkId: network, username: username) {
            return URL(string: urlString)
        }
        return nil
    }

    // MARK: - Security Validation

    /// Check if a URL is safe to open
    /// Mirrors vauchi-core's is_safe_url() implementation
    static func isSafeUrl(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Extract scheme
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return false }
        let scheme = String(trimmed[..<colonIndex]).lowercased()

        // Check blocklist first (explicit deny)
        if blockedSchemes.contains(scheme) { return false }

        // Must be in allowlist
        return allowedSchemes.contains(scheme)
    }

    /// Check if a URL is safe to open using vauchi-core validation
    static func isSafeUrl(_ url: URL) -> Bool {
        return isSafeUrl(url.absoluteString)
    }

    // MARK: - Available Actions

    /// Get the available actions for a field type
    static func availableActions(for type: VauchiFieldType) -> [Action] {
        switch type {
        case .phone:
            return [.call, .sms, .copy]
        case .email:
            return [.email, .copy]
        case .website:
            return [.openUrl, .copy]
        case .address:
            return [.openMaps, .copy]
        case .social:
            return [.openUrl, .copy]
        case .custom:
            return [.copy]
        }
    }

    // MARK: - Action Execution

    /// Open a URL if it's safe
    @MainActor
    static func openUrl(_ url: URL) {
        guard isSafeUrl(url) else {
            print("ContactActions: Blocked unsafe URL: \(url)")
            return
        }
        UIApplication.shared.open(url)
    }

    /// Open a field's primary action
    @MainActor
    static func openField(value: String, type: VauchiFieldType) {
        guard let url = buildUrl(for: value, type: type) else {
            return
        }
        openUrl(url)
    }

    /// Copy a value to the clipboard with automatic expiration
    /// For security, clipboard data expires after 30 seconds
    @MainActor
    static func copyToClipboard(_ value: String) {
        UIPasteboard.general.string = value

        // Clear clipboard after 30 seconds for security
        // This prevents sensitive data from lingering
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            // Only clear if the value is still what we copied
            if UIPasteboard.general.string == value {
                UIPasteboard.general.string = ""
            }
        }
    }
}
