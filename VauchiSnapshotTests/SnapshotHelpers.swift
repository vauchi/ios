// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SnapshotHelpers.swift
// Test helpers for creating configured ViewModels for snapshot tests

import SwiftUI
@testable import Vauchi

/// Creates a VauchiViewModel configured with the given state.
///
/// By default, creates a minimal "has identity, no contacts" state
/// suitable for most view snapshots.
@MainActor
func makeViewModel(
    hasIdentity: Bool = true,
    displayName: String = "Alice",
    publicId: String = "abc123def456",
    card: CardInfo? = nil,
    contacts: [ContactInfo] = [],
    syncState: SyncState = .idle,
    isOnline: Bool = true,
    errorMessage: String? = nil
) -> VauchiViewModel {
    let vm = VauchiViewModel()
    vm.isLoading = false
    vm.hasIdentity = hasIdentity
    vm.errorMessage = errorMessage

    if hasIdentity {
        vm.identity = IdentityInfo(displayName: displayName, publicId: publicId)
        vm.card = card ?? CardInfo(displayName: displayName, fields: [])
    }

    vm.contacts = contacts
    vm.syncState = syncState
    vm.isOnline = isOnline

    return vm
}

/// Sample fields for testing card display
let sampleFields: [FieldInfo] = [
    FieldInfo(id: "f1", fieldType: "email", label: "Personal Email", value: "alice@example.com"),
    FieldInfo(id: "f2", fieldType: "phone", label: "Mobile", value: "+41 79 123 45 67"),
    FieldInfo(id: "f3", fieldType: "website", label: "Website", value: "https://alice.example.com"),
]

/// Sample contacts for testing contact list
let sampleContacts: [ContactInfo] = [
    ContactInfo(id: "c1", displayName: "Bob", verified: true, addedAt: Date()),
    ContactInfo(id: "c2", displayName: "Charlie", verified: true, addedAt: Date()),
    ContactInfo(id: "c3", displayName: "Diana", verified: false, addedAt: Date()),
]
