// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ContactsView.swift
// Phase 1A.2 (core-gui-architecture-alignment): the Contacts tab is now
// a thin iOS shell around `CoreScreenView(screenName: "Contacts")`. Core
// owns the search field, contact list, row actions (archive/hide/delete
// via ListItemAction overflow menu), the "Archived Contacts" and "Find
// Duplicates" screen actions, and the empty-state guidance —
// see `core/vauchi-app/src/ui/contact_list.rs`.
//
// This shell keeps the iOS-specific chrome that isn't part of the
// cross-platform ScreenModel: the NavigationView, a pull-to-refresh
// gesture wired to `viewModel.sync()`, and the onboarding "demo
// contact" banner (which is frontend-only today; moving it into core
// is tracked as a follow-up).

import CoreUIModels
import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let demo = viewModel.demoContact {
                    DemoContactCard(demo: demo)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                CoreScreenView(screenName: "Contacts")
            }
            .navigationTitle(localizationService.t("nav.contacts"))
            .refreshable {
                await viewModel.sync()
            }
        }
    }
}

// MARK: - Demo Contact Card

// Based on: features/demo_contact.feature
// Still rendered by the iOS shell because the onboarding demo banner
// is not yet exposed through core's ContactListEngine. Follow-up to
// move it into an InfoPanel / Banner emitted by core.

struct DemoContactCard: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @ObservedObject private var localizationService = LocalizationService.shared
    let demo: VauchiDemoContact

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.purple)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(demo.displayName)
                            .font(.headline)

                        Text(localizationService.t("contacts.demo_badge"))
                            .font(Font.caption2.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .cornerRadius(CGFloat(tokens.borderRadius.sm))
                    }

                    Text(demo.tipCategory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Dismiss button
                Button(action: {
                    Task {
                        try? await viewModel.dismissDemoContact()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss demo contact")
                .accessibilityHint("Removes the demo contact card from the contacts list")
            }

            // Tip content
            VStack(alignment: .leading, spacing: 8) {
                Text(demo.tipTitle)
                    .font(Font.subheadline.weight(.medium))

                Text(demo.tipContent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(CGFloat(tokens.borderRadius.md))

            // Info text
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)

                Text("This is a demo contact showing how Vauchi updates work")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .accessibilityIdentifier("contacts.demo")
    }
}

#Preview {
    ContactsView()
        .environmentObject(VauchiViewModel())
}
