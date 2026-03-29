// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// RestoreIdentitySheet.swift
// Backup restore flow accessible during onboarding

import SwiftUI

struct RestoreIdentitySheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @State private var backupData = ""
    @State private var password = ""
    @State private var isRestoring = false
    @State private var errorMessage: String?

    let onRestoreComplete: () -> Void

    var canRestore: Bool {
        !backupData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Enter your backup data and password to restore your identity. This will replace any existing identity on this device.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Backup Data") {
                    TextEditor(text: $backupData)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("restore.backupData")
                        .accessibilityLabel("Backup data")
                        .accessibilityHint("Paste your exported backup string here")
                }

                Section("Password") {
                    SecureField("Backup password", text: $password)
                        .accessibilityIdentifier("restore.password")
                        .accessibilityLabel("Backup password")
                        .accessibilityHint("Enter the password used when creating the backup")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: restoreBackup) {
                        HStack {
                            Spacer()
                            if isRestoring {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Restore Identity")
                            Spacer()
                        }
                    }
                    .disabled(!canRestore || isRestoring)
                }
            }
            .navigationTitle("Restore Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func restoreBackup() {
        isRestoring = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.importBackup(
                    data: backupData.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )

                await MainActor.run {
                    dismiss()
                    onRestoreComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRestoring = false
                }
            }
        }
    }
}
