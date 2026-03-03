// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// KeychainService.swift
// Secure storage using iOS Keychain with file-based fallback for simulator

import Foundation
import Security

enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case notFound
    case invalidData
    case deviceLocked // errSecInteractionNotAllowed (-25308)
}

class KeychainService {
    static let shared = KeychainService()

    private let service = "app.vauchi.ios"

    // Track if Keychain is available (may fail in simulator)
    private var useFileStorage = false
    private var fileStoragePath: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Vauchi")
            .appendingPathComponent("keystore")
    }

    private init() {
        #if targetEnvironment(simulator)
            // In simulator, test if Keychain works
            let testKey = "__keychain_test__"
            let testData = Data([0x01, 0x02, 0x03])
            do {
                try saveToKeychain(key: testKey, data: testData)
                _ = try loadFromKeychain(key: testKey)
                try deleteFromKeychain(key: testKey)
                print("KeychainService: Keychain working in simulator")
            } catch {
                print("KeychainService: Keychain unavailable (error: \(error)), using file storage")
                useFileStorage = true
                // Ensure directory exists
                if let path = fileStoragePath {
                    try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                }
            }
        #endif
    }

    // MARK: - Public API

    func save(key: String, data: Data) throws {
        if useFileStorage {
            try saveToFile(key: key, data: data)
        } else {
            try saveToKeychain(key: key, data: data)
        }
    }

    func load(key: String) throws -> Data {
        if useFileStorage {
            try loadFromFile(key: key)
        } else {
            try loadFromKeychain(key: key)
        }
    }

    func delete(key: String) throws {
        if useFileStorage {
            try deleteFromFile(key: key)
        } else {
            try deleteFromKeychain(key: key)
        }
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(key: String, data: Data) throws {
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        // Try to update first
        var status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if status == errSecItemNotFound {
            status = SecItemAdd(saveQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            if status == errSecInteractionNotAllowed {
                throw KeychainError.deviceLocked
            }
            throw KeychainError.unknown(status)
        }
    }

    private func loadFromKeychain(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            if status == errSecInteractionNotAllowed {
                throw KeychainError.deviceLocked
            }
            throw KeychainError.unknown(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    private func deleteFromKeychain(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - File Storage Operations (Fallback for Simulator)

    private func fileURL(for key: String) -> URL? {
        fileStoragePath?.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
    }

    private func saveToFile(key: String, data: Data) throws {
        guard let url = fileURL(for: key) else {
            throw KeychainError.unknown(-1)
        }
        try data.write(to: url, options: .completeFileProtection)
    }

    private func loadFromFile(key: String) throws -> Data {
        guard let url = fileURL(for: key) else {
            throw KeychainError.unknown(-1)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KeychainError.notFound
        }
        return try Data(contentsOf: url)
    }

    private func deleteFromFile(key: String) throws {
        guard let url = fileURL(for: key) else {
            throw KeychainError.unknown(-1)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
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
        try load(key: "storage_key")
    }

    func saveIdentityBackup(_ backup: Data) throws {
        try save(key: "identity_backup", data: backup)
    }

    func loadIdentityBackup() throws -> Data {
        try load(key: "identity_backup")
    }
}
