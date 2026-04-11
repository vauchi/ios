// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MoreView.swift
// Aggregated menu for Settings, Help, and secondary features

import SwiftUI

struct MoreView: View {
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationStack {
            List {
                primarySection
                secondarySection
                legalSection
            }
            .navigationTitle(localizationService.t("nav.more"))
            .navigationBarTitleDisplayMode(.large)
        }
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
                HelpView()
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
                SyncStatusPlaceholderView()
            } label: {
                Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("more.syncStatus")

            NavigationLink {
                LinkedDevicesPlaceholderView()
            } label: {
                Label("Linked Devices", systemImage: "laptopcomputer.and.iphone")
            }
            .accessibilityIdentifier("more.linkedDevices")

            NavigationLink {
                BackupRecoveryPlaceholderView()
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
                PrivacyPolicyPlaceholderView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }
            .accessibilityIdentifier("more.privacyPolicy")
        }
    }
}

// MARK: - Placeholder Views

/// Placeholder for Sync Status (to be replaced with real implementation)
private struct SyncStatusPlaceholderView: View {
    var body: some View {
        placeholderContent(
            title: "Sync Status",
            icon: "arrow.triangle.2.circlepath",
            message: "Sync status details will appear here."
        )
    }
}

/// Placeholder for Linked Devices (to be replaced with real implementation)
private struct LinkedDevicesPlaceholderView: View {
    var body: some View {
        placeholderContent(
            title: "Linked Devices",
            icon: "laptopcomputer.and.iphone",
            message: "Manage your linked devices here."
        )
    }
}

/// Placeholder for Backup & Recovery (to be replaced with real implementation)
private struct BackupRecoveryPlaceholderView: View {
    var body: some View {
        placeholderContent(
            title: "Backup & Recovery",
            icon: "externaldrive.badge.shield",
            message: "Backup and recovery options will appear here."
        )
    }
}

/// Placeholder for Privacy Policy (to be replaced with real implementation)
private struct PrivacyPolicyPlaceholderView: View {
    var body: some View {
        placeholderContent(
            title: "Privacy Policy",
            icon: "hand.raised.fill",
            message: "Privacy policy details will appear here."
        )
    }
}

/// Reusable placeholder layout for coming-soon screens
private func placeholderContent(
    title: String,
    icon: String,
    message: String
) -> some View {
    VStack(spacing: 16) {
        Image(systemName: icon)
            .font(.system(size: 48))
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
        Text(message)
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
}

#Preview {
    MoreView()
}
