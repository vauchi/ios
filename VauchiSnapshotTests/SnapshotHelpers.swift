// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SnapshotHelpers.swift
// Test helpers for creating configured ViewModels for snapshot tests

import SwiftUI
@testable import Vauchi
import VauchiPlatform

/// Creates a VauchiViewModel configured with the given state.
///
/// By default, creates a minimal "has identity, no contacts" state
/// suitable for most view snapshots.
@MainActor
func makeViewModel(
    hasIdentity: Bool = true,
    displayName: String = "Alice",
    publicId: String = "abc123def456",
    card: VauchiContactCard? = nil,
    contacts: [VauchiContact] = [],
    syncState: SyncState = .idle,
    isOnline: Bool = true,
    errorMessage: String? = nil
) -> VauchiViewModel {
    let vm = VauchiViewModel()
    vm.isLoading = false
    vm.hasIdentity = hasIdentity
    vm.errorMessage = errorMessage

    if hasIdentity {
        vm.displayName = displayName
        vm.publicId = publicId
        vm.card = card ?? VauchiContactCard(displayName: displayName, fields: [])
    }

    vm.contacts = contacts
    vm.syncState = syncState
    vm.isOnline = isOnline

    return vm
}

/// Sample fields for testing card display
let sampleFields: [VauchiContactField] = [
    VauchiContactField(id: "f1", fieldType: .email, label: "Personal Email", value: "alice@example.com"),
    VauchiContactField(id: "f2", fieldType: .phone, label: "Mobile", value: "+41 79 123 45 67"),
    VauchiContactField(id: "f3", fieldType: .website, label: "Website", value: "https://alice.example.com"),
]

/// Sample contacts for testing contact list
private func sampleContact(id: String, name: String, verified: Bool) -> VauchiContact {
    VauchiContact(
        id: id,
        displayName: name,
        fingerprint: "",
        isVerified: verified,
        isRecoveryTrusted: false,
        isHidden: false,
        isImported: false,
        card: VauchiContactCard(displayName: name, fields: []),
        addedAt: UInt64(Date().timeIntervalSince1970),
        trustLevel: .standard,
        proposalTrusted: false,
        reciprocity: .unknown
    )
}

let sampleContacts: [VauchiContact] = [
    sampleContact(id: "c1", name: "Bob", verified: true),
    sampleContact(id: "c2", name: "Charlie", verified: true),
    sampleContact(id: "c3", name: "Diana", verified: false),
]
