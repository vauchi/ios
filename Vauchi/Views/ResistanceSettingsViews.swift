// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import VauchiPlatform

// MARK: - Duress Settings

struct DuressSettingsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showPasswordSetup = false
    @State private var showDuressSetup = false
    @State private var showAddDecoy = false
    @State private var decoyName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var duressPin = ""
    @State private var confirmDuressPin = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Label("App Password", systemImage: "lock.fill")
                    Spacer()
                    Text(viewModel.isPasswordEnabled ? "Enabled" : "Not set")
                        .foregroundStyle(viewModel.isPasswordEnabled ? .primary : .secondary)
                }

                HStack {
                    Label("Duress PIN", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    Text(viewModel.isDuressEnabled ? "Enabled" : "Not set")
                        .foregroundStyle(viewModel.isDuressEnabled ? .primary : .secondary)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("When the duress PIN is entered instead of the app password, contacts are replaced with decoy data for plausible deniability.")
            }

            if !viewModel.isPasswordEnabled {
                Section {
                    Button(action: { showPasswordSetup = true }) {
                        Label("Set App Password", systemImage: "lock.badge.plus")
                    }
                } header: {
                    Text("Setup")
                }
            }

            if viewModel.isPasswordEnabled {
                Section {
                    if !viewModel.isDuressEnabled {
                        Button(action: { showDuressSetup = true }) {
                            Label("Set Duress PIN", systemImage: "shield.lefthalf.filled.badge.checkmark")
                        }
                    } else {
                        Button(role: .destructive) {
                            Task {
                                do {
                                    try await viewModel.disableDuress()
                                    successMessage = "Duress PIN disabled"
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("Disable Duress PIN", systemImage: "shield.slash")
                        }
                    }
                } header: {
                    Text("Actions")
                }
            }

            if viewModel.isDuressEnabled {
                Section {
                    if viewModel.decoyContacts.isEmpty {
                        Text("No decoy contacts yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.decoyContacts, id: \.id) { contact in
                            HStack {
                                Text(contact.displayName)
                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await viewModel.deleteDecoyContact(id: contact.id)
                                        } catch {
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button(action: { showAddDecoy = true }) {
                        Label("Add Decoy Contact", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Decoy Contacts")
                } footer: {
                    Text("Fake contacts shown in duress mode. Add enough to look realistic.")
                }
            }

            if !successMessage.isEmpty {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.secondary)
                }
            }
            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Duress PIN")
        .task {
            await viewModel.loadDuressStatus()
            await viewModel.loadDecoyContacts()
        }
        .alert("Set App Password", isPresented: $showPasswordSetup) {
            SecureField("Password", text: $password)
                .accessibilityLabel("App password")
            SecureField("Confirm Password", text: $confirmPassword)
                .accessibilityLabel("Confirm app password")
            Button("Cancel", role: .cancel) {
                password = ""
                confirmPassword = ""
            }
            Button("Set") {
                guard PasscodePolicy.isValid(password) else {
                    errorMessage =
                        "Password must be \(PasscodePolicy.minLength)–\(PasscodePolicy.maxLength) characters"
                    return
                }
                guard password == confirmPassword else {
                    errorMessage = "Passwords do not match"
                    return
                }
                Task {
                    do {
                        try await viewModel.setupAppPassword(password: password)
                        successMessage = "App password set"
                        password = ""
                        confirmPassword = ""
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert("Set Duress PIN", isPresented: $showDuressSetup) {
            SecureField("Duress PIN", text: $duressPin)
                .accessibilityLabel("Duress PIN")
            SecureField("Confirm PIN", text: $confirmDuressPin)
                .accessibilityLabel("Confirm duress PIN")
            Button("Cancel", role: .cancel) {
                duressPin = ""
                confirmDuressPin = ""
            }
            Button("Set") {
                guard PasscodePolicy.isValid(duressPin) else {
                    errorMessage =
                        "PIN must be \(PasscodePolicy.minLength)–\(PasscodePolicy.maxLength) characters"
                    return
                }
                guard duressPin == confirmDuressPin else {
                    errorMessage = "PINs do not match"
                    return
                }
                Task {
                    do {
                        try await viewModel.setupDuressPassword(duressPassword: duressPin)
                        successMessage = "Duress PIN configured"
                        duressPin = ""
                        confirmDuressPin = ""
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert("Add Decoy Contact", isPresented: $showAddDecoy) {
            TextField("Name", text: $decoyName)
                .accessibilityLabel("Decoy contact name")
            Button("Cancel", role: .cancel) {
                decoyName = ""
            }
            Button("Add") {
                let name = decoyName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    do {
                        try await viewModel.addDecoyContact(name: name)
                        successMessage = "Decoy contact added"
                        decoyName = ""
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - Emergency Broadcast

struct EmergencyBroadcastView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var contactIds = ""
    @State private var message = "I may be in danger. Please check on me."
    @State private var includeLocation = false
    @State private var errorMessage = ""
    @State private var successMessage = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Status", systemImage: viewModel.emergencyConfigured ? "megaphone.fill" : "megaphone")
                    Spacer()
                    Text(viewModel.emergencyConfigured ? "Configured" : "Not configured")
                        .foregroundStyle(viewModel.emergencyConfigured ? .primary : .secondary)
                }
            } header: {
                Text("Emergency Broadcast")
            } footer: {
                Text("Send encrypted emergency alerts to trusted contacts. Alerts are indistinguishable from normal card updates.")
            }

            Section {
                TextField("Contact IDs (comma-separated)", text: $contactIds)
                    .autocapitalization(.none)
                    .accessibilityLabel("Emergency contact IDs")
                    .accessibilityHint("Enter contact IDs separated by commas")
                TextField("Alert message", text: $message)
                    .accessibilityLabel("Emergency alert message")
                    .accessibilityHint("The message sent to your emergency contacts")
                Toggle("Include location", isOn: $includeLocation)
                    .accessibilityLabel("Include location in emergency broadcast")
                    .accessibilityHint("When enabled, your location will be sent with the emergency alert")
            } header: {
                Text("Configuration")
            }

            Section {
                Button("Save Configuration") {
                    let ids = contactIds.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                    Task {
                        do {
                            try await viewModel.configureEmergencyBroadcast(contactIds: ids, message: message, includeLocation: includeLocation)
                            successMessage = "Emergency broadcast configured"
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                if viewModel.emergencyConfigured {
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await viewModel.disableEmergencyBroadcast()
                                successMessage = "Emergency broadcast disabled"
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Disable", systemImage: "xmark.circle")
                    }
                }
            } header: {
                Text("Actions")
            }

            if !successMessage.isEmpty {
                Section { Text(successMessage).foregroundStyle(.secondary) }
            }
            if !errorMessage.isEmpty {
                Section { Text(errorMessage).foregroundColor(.red) }
            }
        }
        .navigationTitle("Emergency Broadcast")
        .task {
            await viewModel.loadEmergencyConfig()
        }
    }
}
