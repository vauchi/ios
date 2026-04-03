// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AppEngineService.swift
// Creates PlatformAppEngine using the same credentials as VauchiRepository.

import Foundation
import VauchiPlatform

/// Creates a `PlatformAppEngine` for core-driven screen rendering.
///
/// Uses the same data directory, relay URL, and storage key as `VauchiRepository`.
/// The engine shares the same database — call `invalidateAll()` after mutations
/// via `VauchiPlatform` to keep screens in sync.
enum AppEngineService {
    static func createEngine(
        dataDir: String? = nil,
        relayUrl: String? = nil
    ) throws -> PlatformAppEngine {
        let dir = dataDir ?? VauchiRepository.defaultDataDir()
        let url = relayUrl ?? SettingsService.shared.relayUrl

        // Reuse the same key retrieval as VauchiRepository
        let storageKeyBytes = try VauchiRepository.getOrCreateStorageKey(dataDir: dir)

        return try PlatformAppEngine(
            dataDir: dir,
            relayUrl: url,
            storageKeyBytes: storageKeyBytes
        )
    }
}
