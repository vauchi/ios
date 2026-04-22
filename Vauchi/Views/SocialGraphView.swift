// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SocialGraphView.swift
// Phase 1A.5 (core-gui-architecture-alignment): the Contact Network
// screen is now a thin iOS shell around
// `CoreScreenView(screenName: "social_graph")`. Core's
// `SocialGraphEngine` (see `core/vauchi-app/src/ui/social_graph.rs`)
// owns the network summary, trust-level filter chip row, and per-trust-
// level contact sections. Tapping a contact emits `OpenContact`, which
// `AppEngine` routes to ContactDetail — no iOS routing needed.
//
// Reached from `SettingsView` via `NavigationLink(destination: SocialGraphView())`,
// so no NavigationView wrapper here (the parent owns navigation).
//
// The `ContactTrustLevel` enum stays in this file because
// `ContactDetailView` / `ContactDetailComponents.TrustLevelBadge` still
// use it as a display-side mapping from `MobileContactTrustLevel`
// (ADR-034). Moving it into core alongside `SocialTrustLevel` is a
// follow-up.

import SwiftUI
import VauchiPlatform

// MARK: - Trust Level

/// Display properties for core's 4-tier trust level (ADR-021/034).
/// Mapped from `MobileContactTrustLevel` — never re-derived from booleans.
enum ContactTrustLevel: Comparable {
    case cautious
    case standard
    case high
    case verified

    init(from mobile: MobileContactTrustLevel) {
        switch mobile {
        case .cautious: self = .cautious
        case .standard: self = .standard
        case .high: self = .high
        case .verified: self = .verified
        }
    }

    var displayName: String {
        switch self {
        case .cautious: "Needs Re-verification"
        case .standard: "Not Verified"
        case .high: "High Trust"
        case .verified: "Verified"
        }
    }

    var iconName: String {
        switch self {
        case .cautious: "exclamationmark.triangle.fill"
        case .standard: "person.crop.circle.badge.questionmark"
        case .high: "checkmark.shield.fill"
        case .verified: "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .cautious: .orange
        case .standard: .secondary
        case .high: .blue
        case .verified: .green
        }
    }

    var sectionFooter: String {
        switch self {
        case .cautious:
            "These contacts recovered their identity. Verify them again before trusting sensitive information."
        case .standard:
            "Consider verifying these contacts' fingerprints in person for stronger security."
        case .high:
            "These contacts were verified via proximity (NFC or Bluetooth)."
        case .verified:
            "You have verified these contacts' identities in person."
        }
    }
}

// MARK: - Social Graph View

struct SocialGraphView: View {
    var body: some View {
        CoreScreenView(screenName: "social_graph")
    }
}

#Preview {
    NavigationView {
        SocialGraphView()
    }
    .environmentObject(VauchiViewModel())
}
