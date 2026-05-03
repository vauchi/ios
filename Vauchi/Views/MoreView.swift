// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MoreView.swift
// Phase 1A.4 (core-gui-architecture-alignment): every row that used to
// navigate to a placeholder view now links to a `CoreScreenView`. Core
// already ships `sync`, `device_management`, `backup`, and `privacy`
// screens — the iOS shell only provides the list + NavigationLinks.

import SwiftUI

struct MoreView: View {
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            List {
                primarySection
                secondarySection
                legalSection
            }
            .navigationTitle(localizationService.t("nav.more"))
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var primarySection: some View {
        Section {
            NavigationLink {
                CoreScreenView(screenName: "Settings")
            } label: {
                Label(
                    localizationService.t("nav.settings"),
                    systemImage: "gear"
                )
            }
            .accessibilityIdentifier("more.settings")

            NavigationLink {
                CoreScreenView(screenName: "help")
            } label: {
                Label(
                    localizationService.t("nav.help"),
                    systemImage: "questionmark.circle"
                )
            }
            .accessibilityIdentifier("more.help")
        }
    }

    private var secondarySection: some View {
        Section {
            NavigationLink {
                CoreScreenView(screenName: "Sync")
            } label: {
                Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("more.syncStatus")

            NavigationLink {
                CoreScreenView(screenName: "DeviceManagement")
            } label: {
                Label("Linked Devices", systemImage: "laptopcomputer.and.iphone")
            }
            .accessibilityIdentifier("more.linkedDevices")

            NavigationLink {
                CoreScreenView(screenName: "DeviceReplacement")
            } label: {
                Label("Replace Device", systemImage: "iphone.and.arrow.forward")
            }
            .accessibilityIdentifier("more.deviceReplacement")

            NavigationLink {
                CoreScreenView(screenName: "Backup")
            } label: {
                Label("Backup & Recovery", systemImage: "externaldrive.badge.shield")
            }
            .accessibilityIdentifier("more.backupRecovery")

            NavigationLink {
                ImportContactsView()
            } label: {
                Label("Import Contacts", systemImage: "person.crop.rectangle.stack")
            }
            .accessibilityIdentifier("more.importContacts")
        }
    }

    private var legalSection: some View {
        Section {
            NavigationLink {
                CoreScreenView(screenName: "Privacy")
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }
            .accessibilityIdentifier("more.privacyPolicy")
        }
    }
}

#Preview {
    MoreView()
}
