// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ConsentSettingsView.swift
// GDPR consent management with toggle rows and history

import SwiftUI

struct ConsentSettingsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var consentStates: [VauchiConsentType: Bool] = [:]

    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .accessibilityLabel("Loading consent settings")
                        Spacer()
                    }
                }
            } else {
                // Consent toggles
                Section {
                    ForEach(VauchiConsentType.allCases, id: \.rawValue) { consentType in
                        ConsentToggleRow(
                            consentType: consentType,
                            isGranted: Binding(
                                get: { consentStates[consentType] ?? false },
                                set: { newValue in
                                    Task {
                                        await toggleConsent(consentType, granted: newValue)
                                    }
                                }
                            )
                        )
                    }
                } header: {
                    Text("Consent Preferences")
                } footer: {
                    Text("You can change your consent preferences at any time. Some features may be limited if consent is revoked.")
                }

                // Consent history
                if !viewModel.consentRecords.isEmpty {
                    Section {
                        ForEach(viewModel.consentRecords) { record in
                            ConsentRecordRow(record: record)
                        }
                    } header: {
                        Text("Consent History")
                    } footer: {
                        Text("A record of all consent changes for your data protection rights.")
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Consent Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadConsentState()
            }
        }
        .refreshable {
            await loadConsentState()
        }
    }

    // MARK: - Actions

    private func loadConsentState() async {
        isLoading = true
        errorMessage = nil

        do {
            try await viewModel.loadConsentRecords()

            // Query consent status from core for each type
            var states: [VauchiConsentType: Bool] = [:]
            for consentType in VauchiConsentType.allCases {
                let status = try viewModel.getConsentStatus(consentType)
                states[consentType] = status.granted
            }
            consentStates = states
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func toggleConsent(_ type: VauchiConsentType, granted: Bool) async {
        errorMessage = nil

        do {
            if granted {
                try await viewModel.grantConsent(type)
            } else {
                try await viewModel.revokeConsent(type)
            }
            consentStates[type] = granted
        } catch {
            // Revert the toggle on failure
            consentStates[type] = !granted
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Consent Toggle Row

struct ConsentToggleRow: View {
    let consentType: VauchiConsentType
    @Binding var isGranted: Bool

    var consentDescription: String {
        switch consentType {
        case .dataProcessing:
            "Allow processing of your contact data for core functionality."
        case .contactSharing:
            "Allow sharing your contact card with others via QR exchange."
        case .recoveryVouching:
            "Allow participating in identity recovery vouching for contacts."
        }
    }

    var consentIcon: String {
        switch consentType {
        case .dataProcessing: "gearshape.2"
        case .contactSharing: "person.2"
        case .recoveryVouching: "person.badge.key"
        }
    }

    var body: some View {
        Toggle(isOn: $isGranted) {
            VStack(alignment: .leading, spacing: 2) {
                Label(consentType.displayName, systemImage: consentIcon)
                    .accessibilityHidden(true)
                Text(consentDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tint(.cyan)
        .accessibilityLabel("\(consentType.displayName): \(consentDescription)")
        .accessibilityValue(isGranted ? "Granted" : "Revoked")
        .accessibilityHint("Double tap to \(isGranted ? "revoke" : "grant") consent")
    }
}

// MARK: - Consent Record Row

struct ConsentRecordRow: View {
    let record: VauchiConsentRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.consentType.displayName)
                        .font(.subheadline)
                    Text(record.granted ? "Granted" : "Revoked")
                        .font(.caption)
                        .foregroundColor(record.granted ? .green : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(record.granted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        )
                }

                HStack(spacing: 8) {
                    Text(record.date, style: .date)
                    Text(record.date, style: .time)
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                if let version = record.policyVersion {
                    Text("Policy v\(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: record.granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(record.granted ? .green : .orange)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.consentType.displayName) \(record.granted ? "granted" : "revoked") on \(record.date.formatted())")
    }
}

#Preview {
    NavigationView {
        ConsentSettingsView()
            .environmentObject(VauchiViewModel())
    }
}
