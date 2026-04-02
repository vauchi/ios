// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AccountDeletionView.swift
// GDPR account deletion with 7-day grace period

import SwiftUI

struct AccountDeletionView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showScheduleConfirmation = false
    @State private var showCancelConfirmation = false

    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .accessibilityLabel("Loading account deletion status")
                        Spacer()
                    }
                }
            } else {
                switch viewModel.deletionState {
                case .none:
                    noDeletionSection
                case .scheduled:
                    scheduledDeletionSection
                case .executed:
                    executedDeletionSection
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // Information section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What happens when you delete your account", systemImage: "info.circle")
                        .font(.subheadline.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text("All your contacts, cards, and identity data will be permanently erased.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Your contacts will no longer be able to reach you or see your card updates.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("This action cannot be undone after the grace period expires.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Information")
            }
        }
        .navigationTitle("Delete Identity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadState()
            }
        }
        .alert("Delete Account?", isPresented: $showScheduleConfirmation) {
            Button(localizationService.t("action.cancel"), role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task {
                    await scheduleDeletion()
                }
            }
        } message: {
            Text("Your account will be scheduled for deletion. You will have 7 days to cancel before your data is permanently erased.")
        }
        .alert("Cancel Deletion?", isPresented: $showCancelConfirmation) {
            Button("Keep Scheduled", role: .cancel) {}
            Button("Cancel Deletion") {
                Task {
                    await cancelDeletion()
                }
            }
        } message: {
            Text("Your account deletion will be cancelled and your data will be preserved.")
        }
    }

    // MARK: - State Sections

    private var noDeletionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundColor(.green)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Account Active")
                            .font(.headline)
                        Text("Your account is in good standing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 4)

            Button(role: .destructive, action: { showScheduleConfirmation = true }) {
                HStack {
                    Spacer()
                    Label("Schedule Deletion", systemImage: "trash")
                    Spacer()
                }
            }
            .accessibilityLabel("Schedule account deletion")
            .accessibilityHint("Begin the 7-day deletion process for your account")
        } header: {
            Text("Status")
        } footer: {
            Text("Once scheduled, you have a 7-day grace period to cancel the deletion.")
        }
    }

    private var scheduledDeletionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Deletion Scheduled")
                            .font(.headline)
                            .foregroundColor(.orange)
                        if let info = viewModel.deletionInfo {
                            Text("Your account will be deleted in \(info.daysRemaining) day(s).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if let info = viewModel.deletionInfo {
                    Divider()

                    HStack {
                        Text("Scheduled on")
                        Spacer()
                        Text(info.scheduledDate, style: .date)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Will execute on")
                        Spacer()
                        Text(info.executeDate, style: .date)
                            .foregroundColor(.red)
                    }

                    HStack {
                        Text("Days remaining")
                        Spacer()
                        Text("\(info.daysRemaining)")
                            .foregroundColor(.orange)
                            .bold()
                    }
                }
            }
            .padding(.vertical, 4)

            Button(action: { showCancelConfirmation = true }) {
                HStack {
                    Spacer()
                    Label("Cancel Deletion", systemImage: "xmark.circle")
                        .foregroundColor(.cyan)
                    Spacer()
                }
            }
            .accessibilityLabel("Cancel deletion")
            .accessibilityHint("Stop the deletion process and keep your account")
        } header: {
            Text("Status")
        } footer: {
            Text("You can cancel the deletion at any time during the 7-day grace period. After that, your data will be permanently erased.")
        }
    }

    private var executedDeletionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Account Deleted")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text("Your account data has been permanently erased.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Status")
        }
    }

    // MARK: - Actions

    private func loadState() async {
        isLoading = true
        errorMessage = nil

        do {
            try await viewModel.loadDeletionState()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func scheduleDeletion() async {
        errorMessage = nil

        do {
            try await viewModel.scheduleIdentityDeletion()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelDeletion() async {
        errorMessage = nil

        do {
            try await viewModel.cancelIdentityDeletion()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationView {
        AccountDeletionView()
            .environmentObject(VauchiViewModel())
    }
}
