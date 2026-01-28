// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContentUpdateService.swift
// Manages remote content updates (networks, locales, themes, help)

import Combine
import Foundation

/// Status of content update availability
enum ContentUpdateStatus {
    case upToDate
    case updatesAvailable([ContentType])
    case checkFailed(String)
    case disabled
}

/// Types of content that can be updated
enum ContentType: String, CaseIterable {
    case networks
    case locales
    case themes
    case help
}

/// Result of applying content updates
struct ContentApplyResult {
    let applied: [ContentType]
    let failed: [(ContentType, String)]
}

/// Service for managing remote content updates
final class ContentUpdateService: ObservableObject {
    static let shared = ContentUpdateService()

    // MARK: - Published Properties

    @Published private(set) var isChecking = false
    @Published private(set) var isUpdating = false
    @Published private(set) var updateStatus: ContentUpdateStatus = .upToDate
    @Published private(set) var lastCheckTime: Date?

    // MARK: - Settings

    /// Whether remote content updates are enabled
    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            if !newValue {
                updateStatus = .disabled
            }
        }
    }

    /// Content update base URL
    var contentUrl: String {
        get { defaults.string(forKey: Keys.contentUrl) ?? Defaults.contentUrl }
        set { defaults.set(newValue, forKey: Keys.contentUrl) }
    }

    /// Check interval in seconds
    var checkIntervalSeconds: Int {
        get { defaults.integer(forKey: Keys.checkInterval) == 0 ? Defaults.checkInterval : defaults.integer(forKey: Keys.checkInterval) }
        set { defaults.set(newValue, forKey: Keys.checkInterval) }
    }

    // MARK: - Private Properties

    private let defaults: UserDefaults
    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let enabled = "vauchi.content.enabled"
        static let contentUrl = "vauchi.content.url"
        static let checkInterval = "vauchi.content.checkInterval"
        static let lastCheck = "vauchi.content.lastCheck"
        static let cachedManifest = "vauchi.content.manifest"
    }

    private enum Defaults {
        static let contentUrl = "https://vauchi.app/app-files/"
        static let checkInterval = 3600 // 1 hour
    }

    // MARK: - Initialization

    private convenience init() {
        self.init(defaults: .standard, session: .shared)
    }

    init(defaults: UserDefaults, session: URLSession) {
        self.defaults = defaults
        self.session = session

        // Register defaults
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.contentUrl: Defaults.contentUrl,
            Keys.checkInterval: Defaults.checkInterval,
        ])

        // Load last check time
        if let timestamp = defaults.object(forKey: Keys.lastCheck) as? Date {
            lastCheckTime = timestamp
        }

        // Initial status
        if !isEnabled {
            updateStatus = .disabled
        }
    }

    // MARK: - Public Methods

    /// Check for available content updates
    @MainActor
    func checkForUpdates() async {
        guard isEnabled else {
            updateStatus = .disabled
            return
        }

        guard !isChecking else { return }

        isChecking = true
        defer { isChecking = false }

        do {
            let manifest = try await fetchManifest()
            let updates = compareVersions(remote: manifest)

            lastCheckTime = Date()
            defaults.set(lastCheckTime, forKey: Keys.lastCheck)

            if updates.isEmpty {
                updateStatus = .upToDate
            } else {
                updateStatus = .updatesAvailable(updates)
            }
        } catch {
            updateStatus = .checkFailed(error.localizedDescription)
        }
    }

    /// Apply available content updates
    @MainActor
    func applyUpdates() async throws -> ContentApplyResult {
        guard isEnabled else {
            throw ContentUpdateError.disabled
        }

        guard case let .updatesAvailable(types) = updateStatus else {
            return ContentApplyResult(applied: [], failed: [])
        }

        guard !isUpdating else {
            throw ContentUpdateError.alreadyUpdating
        }

        isUpdating = true
        defer { isUpdating = false }

        var applied: [ContentType] = []
        var failed: [(ContentType, String)] = []

        let manifest = try await fetchManifest()

        for type in types {
            do {
                try await downloadAndCache(type: type, manifest: manifest)
                applied.append(type)
            } catch {
                failed.append((type, error.localizedDescription))
            }
        }

        // Update status
        if failed.isEmpty {
            updateStatus = .upToDate
        } else if !applied.isEmpty {
            // Partial success - recheck what's still needed
            await checkForUpdates()
        }

        return ContentApplyResult(applied: applied, failed: failed)
    }

    /// Check if enough time has passed for a new check
    func shouldCheckNow() -> Bool {
        guard isEnabled else { return false }
        guard let lastCheck = lastCheckTime else { return true }

        let elapsed = Date().timeIntervalSince(lastCheck)
        return elapsed >= Double(checkIntervalSeconds)
    }

    /// Get cached social networks
    func getCachedNetworks() -> [SocialNetwork]? {
        guard let data = getCachedContent(type: .networks) else { return nil }
        return try? JSONDecoder().decode([SocialNetwork].self, from: data)
    }

    // MARK: - Private Methods

    private func fetchManifest() async throws -> ContentManifest {
        let url = URL(string: contentUrl)!.appendingPathComponent("manifest.json")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw ContentUpdateError.httpError
        }

        return try JSONDecoder().decode(ContentManifest.self, from: data)
    }

    private func compareVersions(remote: ContentManifest) -> [ContentType] {
        var updates: [ContentType] = []

        // Get cached manifest
        guard let cachedData = defaults.data(forKey: Keys.cachedManifest),
              let cached = try? JSONDecoder().decode(ContentManifest.self, from: cachedData)
        else {
            // No cache - all content types need update
            if remote.content.networks != nil { updates.append(.networks) }
            if remote.content.locales != nil { updates.append(.locales) }
            if remote.content.themes != nil { updates.append(.themes) }
            return updates
        }

        // Compare versions
        if let remoteNetworks = remote.content.networks,
           cached.content.networks?.version != remoteNetworks.version
        {
            updates.append(.networks)
        }

        if let remoteLocales = remote.content.locales,
           cached.content.locales?.version != remoteLocales.version
        {
            updates.append(.locales)
        }

        if let remoteThemes = remote.content.themes,
           cached.content.themes?.version != remoteThemes.version
        {
            updates.append(.themes)
        }

        return updates
    }

    private func downloadAndCache(type: ContentType, manifest: ContentManifest) async throws {
        let entry: ContentEntry?
        let filename: String

        switch type {
        case .networks:
            entry = manifest.content.networks
            filename = "networks.json"
        case .locales:
            // Download English for now
            guard let locales = manifest.content.locales,
                  let enFile = locales.files["en"]
            else {
                throw ContentUpdateError.noContent
            }
            let url = URL(string: contentUrl)!
                .appendingPathComponent(locales.path)
                .appendingPathComponent(enFile.path)
            try await downloadAndVerify(url: url, checksum: enFile.checksum, filename: "en.json", type: type)
            return
        case .themes:
            entry = manifest.content.themes
            filename = "themes.json"
        case .help:
            // Help not implemented yet
            return
        }

        guard let entry = entry else {
            throw ContentUpdateError.noContent
        }

        let url = URL(string: contentUrl)!.appendingPathComponent(entry.path)
        try await downloadAndVerify(url: url, checksum: entry.checksum, filename: filename, type: type)

        // Save manifest after successful update
        if let manifestData = try? JSONEncoder().encode(manifest) {
            defaults.set(manifestData, forKey: Keys.cachedManifest)
        }
    }

    private func downloadAndVerify(url: URL, checksum: String, filename: String, type: ContentType) async throws {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw ContentUpdateError.httpError
        }

        // Verify checksum
        let actualChecksum = computeChecksum(data)
        guard actualChecksum == checksum else {
            throw ContentUpdateError.checksumMismatch
        }

        // Save to cache
        try saveCachedContent(type: type, filename: filename, data: data)
    }

    private func computeChecksum(_ data: Data) -> String {
        // SHA-256 using CommonCrypto
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
    }

    private func getCacheDirectory() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("vauchi-content", isDirectory: true)
    }

    private func getCachedContent(type: ContentType) -> Data? {
        let dir = getCacheDirectory().appendingPathComponent(type.rawValue, isDirectory: true)
        let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        guard let file = files?.first else { return nil }
        return try? Data(contentsOf: file)
    }

    private func saveCachedContent(type: ContentType, filename: String, data: Data) throws {
        let dir = getCacheDirectory().appendingPathComponent(type.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent(filename)

        // Atomic write
        let tempFile = dir.appendingPathComponent(filename + ".tmp")
        try data.write(to: tempFile)
        try FileManager.default.moveItem(at: tempFile, to: file)
    }
}

// MARK: - Supporting Types

struct ContentManifest: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let baseUrl: String
    let content: ContentIndex

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case baseUrl = "base_url"
        case content
    }
}

struct ContentIndex: Codable {
    let networks: ContentEntry?
    let locales: LocalesEntry?
    let themes: ContentEntry?
    let help: LocalesEntry?
}

struct ContentEntry: Codable {
    let version: String
    let path: String
    let checksum: String
    let minAppVersion: String

    enum CodingKeys: String, CodingKey {
        case version, path, checksum
        case minAppVersion = "min_app_version"
    }
}

struct LocalesEntry: Codable {
    let version: String
    let path: String
    let minAppVersion: String
    let files: [String: FileEntry]

    enum CodingKeys: String, CodingKey {
        case version, path, files
        case minAppVersion = "min_app_version"
    }
}

struct FileEntry: Codable {
    let path: String
    let checksum: String
}

struct SocialNetwork: Codable {
    let id: String
    let name: String
    let url: String
}

enum ContentUpdateError: LocalizedError {
    case disabled
    case alreadyUpdating
    case httpError
    case checksumMismatch
    case noContent

    var errorDescription: String? {
        switch self {
        case .disabled: return "Content updates are disabled"
        case .alreadyUpdating: return "Already updating content"
        case .httpError: return "Failed to download content"
        case .checksumMismatch: return "Content integrity check failed"
        case .noContent: return "No content available"
        }
    }
}

// CommonCrypto import for SHA-256
import CommonCrypto
