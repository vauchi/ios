// SettingsView.swift
// Settings and backup view

import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var relayUrl = SettingsService.shared.relayUrl
    @State private var editingRelayUrl = ""
    @State private var showRelayEdit = false
    @State private var showInvalidUrlAlert = false

    var body: some View {
        NavigationView {
            List {
                // Identity section
                Section("Identity") {
                    HStack {
                        Text("Display Name")
                        Spacer()
                        Text(viewModel.identity?.displayName ?? "Unknown")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Public ID")
                        Spacer()
                        if let publicId = viewModel.identity?.publicId {
                            Text(String(publicId.prefix(16)) + "...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                        } else {
                            Text("Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    .contextMenu {
                        if let publicId = viewModel.identity?.publicId {
                            Button(action: {
                                UIPasteboard.general.string = publicId
                            }) {
                                Label("Copy Full ID", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }

                // Sync section
                Section {
                    HStack {
                        Text("Relay Server")
                        Spacer()
                        Text(relayUrl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .onTapGesture {
                        editingRelayUrl = relayUrl
                        showRelayEdit = true
                    }

                    Button(action: { Task { await viewModel.sync() } }) {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            SyncStatusBadge(state: viewModel.syncState)
                        }
                    }
                    .disabled(viewModel.syncState == .syncing)

                    if let lastSync = viewModel.lastSyncTime {
                        HStack {
                            Text("Last Synced")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }

                    if viewModel.pendingUpdates > 0 {
                        HStack {
                            Text("Pending Updates")
                            Spacer()
                            Text("\(viewModel.pendingUpdates)")
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Sync keeps your contacts up to date across devices.")
                }

                // Backup section
                Section {
                    Button(action: { showExportSheet = true }) {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }

                    Button(action: { showImportSheet = true }) {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Back up your identity to restore it on another device or after reinstalling.")
                }

                // Security section
                Section("Security") {
                    NavigationLink(destination: LinkedDevicesView()) {
                        Label("Linked Devices", systemImage: "laptopcomputer.and.iphone")
                    }

                    NavigationLink(destination: RecoveryView()) {
                        Label("Recovery", systemImage: "person.badge.key")
                    }
                }

                // About section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/vauchi")!) {
                        HStack {
                            Label("GitHub", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Vauchi")
                        Spacer()
                        Text("Privacy-focused contact exchange")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showExportSheet) {
                ExportBackupSheet()
            }
            .sheet(isPresented: $showImportSheet) {
                ImportBackupSheet()
            }
            .alert("Edit Relay URL", isPresented: $showRelayEdit) {
                TextField("Relay URL", text: $editingRelayUrl)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    saveRelayUrl()
                }
            } message: {
                Text("Enter the secure WebSocket URL of your relay server (wss://).")
            }
            .alert("Invalid URL", isPresented: $showInvalidUrlAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter a valid secure WebSocket URL starting with wss://. Unencrypted connections (ws://) are not allowed for security.")
            }
            .onAppear {
                relayUrl = SettingsService.shared.relayUrl
            }
        }
    }

    private func saveRelayUrl() {
        let trimmed = editingRelayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if SettingsService.shared.isValidRelayUrl(trimmed) {
            SettingsService.shared.relayUrl = trimmed
            relayUrl = trimmed
        } else {
            showInvalidUrlAlert = true
        }
    }
}

struct SyncStatusBadge: View {
    let state: SyncState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .success(let added, let updated, let sent):
            if added + updated + sent > 0 {
                Text("\(added + updated + sent) changes")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("Up to date")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }
}

struct LinkedDevicesView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.cyan)
                        .frame(width: 32)
                    VStack(alignment: .leading) {
                        Text("This Device")
                            .font(.body)
                        Text("iPhone - Current")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("Manage devices that have access to your identity. Device linking will be available in a future update.")
            }

            Section {
                Button(action: {}) {
                    Label("Link New Device", systemImage: "plus.circle")
                }
                .disabled(true) // Not implemented yet
            }
        }
        .navigationTitle("Linked Devices")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExportBackupSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isExporting = false
    @State private var exportedData: String?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var isAuthenticated = false

    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var passwordStrength: String {
        if password.count < 8 {
            return "Too short (min 8 characters)"
        } else if password.count < 12 {
            return "Fair"
        } else {
            return "Strong"
        }
    }

    var passwordStrengthColor: Color {
        if password.count < 8 {
            return .red
        } else if password.count < 12 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        NavigationView {
            if !isAuthenticated {
                // Biometric authentication required first
                VStack(spacing: 20) {
                    Image(systemName: "faceid")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)

                    Text("Authentication Required")
                        .font(.title2)

                    Text("Exporting your backup requires Face ID or Touch ID authentication to protect your identity.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button(action: authenticateWithBiometrics) {
                        Label("Authenticate", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
                .navigationTitle("Export Backup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onAppear {
                    authenticateWithBiometrics()
                }
            } else {
                // Authenticated - show export form
                Form {
                    Section {
                        SecureField("Password", text: $password)
                        SecureField("Confirm Password", text: $confirmPassword)

                        if !password.isEmpty {
                            HStack {
                                Text("Strength:")
                                Text(passwordStrength)
                                    .foregroundColor(passwordStrengthColor)
                            }
                            .font(.caption)
                        }

                        if !password.isEmpty && !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords don't match")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } header: {
                        Text("Encrypt Backup")
                    } footer: {
                        Text("Your backup will be encrypted with this password. Store it safely - you'll need it to restore your identity.")
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }

                    Section {
                        Button(action: exportBackup) {
                            HStack {
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                } else {
                                    Text("Export")
                                }
                                Spacer()
                            }
                        }
                        .disabled(!passwordsMatch || password.count < 8 || isExporting)
                    }
                }
                .navigationTitle("Export Backup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    if let data = exportedData {
                        ShareSheet(items: [data])
                    }
                }
            }
        }
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to export your identity backup"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        isAuthenticated = true
                        errorMessage = nil
                    } else {
                        errorMessage = authError?.localizedDescription ?? "Authentication failed"
                    }
                }
            }
        } else {
            // Biometrics not available, fall back to device passcode
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to export your identity backup"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        isAuthenticated = true
                        errorMessage = nil
                    } else {
                        errorMessage = authError?.localizedDescription ?? "Authentication failed"
                    }
                }
            }
        }
    }

    private func exportBackup() {
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let backup = try await viewModel.exportBackup(password: password)
                exportedData = backup
                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ImportBackupSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showFilePicker = false
    @State private var backupData: String?
    @State private var password = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    @State private var isAuthenticated = false

    var body: some View {
        NavigationView {
            if !isAuthenticated {
                // Biometric authentication required first
                VStack(spacing: 20) {
                    Image(systemName: "faceid")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)

                    Text("Authentication Required")
                        .font(.title2)

                    Text("Importing a backup requires Face ID or Touch ID authentication to protect your identity.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button(action: authenticateWithBiometrics) {
                        Label("Authenticate", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onAppear {
                    authenticateWithBiometrics()
                }
            } else {
                // Authenticated - show import UI
                VStack(spacing: 20) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)

                    Text("Import Backup")
                        .font(.title)

                    if viewModel.hasIdentity {
                        Text("Warning: Importing a backup will replace your current identity!")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if backupData != nil {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Backup file loaded")
                            }

                            SecureField("Enter backup password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)

                            Button(action: {
                                if viewModel.hasIdentity {
                                    showConfirmation = true
                                } else {
                                    importBackup()
                                }
                            }) {
                                HStack {
                                    if isImporting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Restore Identity")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(password.isEmpty ? Color.gray : Color.cyan)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(password.isEmpty || isImporting)
                            .padding(.horizontal)
                        }
                    } else {
                        Text("Select a backup file to restore your identity")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showFilePicker = true }) {
                            Label("Choose File", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.cyan)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.plainText, .data],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileSelection(result)
                }
                .alert("Replace Identity?", isPresented: $showConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Replace", role: .destructive) {
                        importBackup()
                    }
                } message: {
                    Text("This will permanently replace your current identity. Make sure you have a backup of your current identity first.")
                }
            }
        }
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to import your identity backup"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        isAuthenticated = true
                        errorMessage = nil
                    } else {
                        errorMessage = authError?.localizedDescription ?? "Authentication failed"
                    }
                }
            }
        } else {
            // Biometrics not available, fall back to device passcode
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to import your identity backup"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        isAuthenticated = true
                        errorMessage = nil
                    } else {
                        errorMessage = authError?.localizedDescription ?? "Authentication failed"
                    }
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                // Access the file
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Could not access file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try String(contentsOf: url, encoding: .utf8)
                backupData = data.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                errorMessage = "Could not read file: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        guard let data = backupData else { return }

        isImporting = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.importBackup(data: data, password: password)
                dismiss()
            } catch {
                if error.localizedDescription.contains("decrypt") ||
                   error.localizedDescription.contains("password") {
                    errorMessage = "Incorrect password"
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isImporting = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(VauchiViewModel())
}
