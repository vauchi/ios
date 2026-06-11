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
/// Identity display-name / public-id / card are no longer held on
/// VauchiViewModel (G4 2026-06-06 — those projections were core-owned and
/// dead). The card/identity-detail snapshots render core wire types
/// (PreviewComponent etc.) directly, so the helper only seeds the shell
/// state the surviving views read.
@MainActor
func makeViewModel(
    hasIdentity: Bool = true,
    syncState: SyncState = .idle,
    isOnline: Bool = true,
    errorMessage: String? = nil
) -> VauchiViewModel {
    let vm = VauchiViewModel()
    vm.isLoading = false
    vm.hasIdentity = hasIdentity
    vm.errorMessage = errorMessage
    vm.syncState = syncState
    vm.isOnline = isOnline

    return vm
}
