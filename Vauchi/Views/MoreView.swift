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
    @EnvironmentObject var viewModel: VauchiViewModel
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

            // Phase 3 of `2026-05-03-core-file-picker-command`:
            // emit core's `import_contacts` action instead of pushing
            // a custom .fileImporter view. Sequence:
            //   1. navigate the engine to AppScreen::More so the
            //      MoreEngine is the active engine
            //   2. emit `import_contacts` action_id, which MoreEngine
            //      maps to ExchangeCommand::FilePickFromUser
            //   3. AppViewModel.handleExchangeCommands picks up the
            //      command, sets `pendingFilePick`, CoreScreenView's
            //      `.fileImporter` opens
            //   4. picker resolves → FilePickedFromUser routes via
            //      AppScreen::More → Vauchi::import_contacts_from_vcf
            //      → toast with imported / skipped counts
            // No visual transition: this view stays mounted while
            // engine state moves; iOS doesn't render core's More
            // screen here.
            Button {
                guard let coreVM = viewModel.coreViewModel else { return }
                coreVM.navigateTo(screenJson: "\"More\"")
                coreVM.handleAction(.actionPressed(actionId: "import_contacts"))
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
