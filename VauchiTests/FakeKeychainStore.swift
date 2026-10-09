// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import Vauchi

/// An in-memory `KeychainStoring` that can fail every call, as a locked
/// device's keychain does.
final class FakeKeychainStore: KeychainStoring {
    var items: [String: Data] = [:]
    var failure: Error?

    func save(key: String, data: Data) throws {
        if let failure {
            throw failure
        }
        items[key] = data
    }

    func load(key: String) throws -> Data {
        if let failure {
            throw failure
        }
        guard let data = items[key] else { throw KeychainServiceError.notFound }
        return data
    }

    func delete(key: String) throws {
        if let failure {
            throw failure
        }
        items[key] = nil
    }
}
