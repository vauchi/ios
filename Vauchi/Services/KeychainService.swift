// KeychainService.swift
// Secure storage using iOS Keychain

import Foundation
import Security

enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case notFound
    case invalidData
}

class KeychainService {
    static let shared = KeychainService()

    private let service = "app.vauchi.ios"

    private init() {}

    // MARK: - Save

    func save(key: String, data: Data) throws {
        // Build the query for saving
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Use more secure protection: requires first unlock after device restart
            // This provides additional protection while keeping the app functional
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Build query for update (without kSecValueData)
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        // Try to update first (atomic operation)
        var status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            status = SecItemAdd(saveQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Load

    func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.unknown(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    // MARK: - Delete

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Convenience

    func saveString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(key: key, data: data)
    }

    func loadString(forKey key: String) throws -> String {
        let data = try load(key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    // MARK: - Vauchi specific

    func saveStorageKey(_ key: Data) throws {
        try save(key: "storage_key", data: key)
    }

    func loadStorageKey() throws -> Data {
        return try load(key: "storage_key")
    }

    func saveIdentityBackup(_ backup: Data) throws {
        try save(key: "identity_backup", data: backup)
    }

    func loadIdentityBackup() throws -> Data {
        return try load(key: "identity_backup")
    }
}
