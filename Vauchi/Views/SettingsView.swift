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
    @State private var showEditNameAlert = false
    @State private var editingDisplayName = ""

    // Accessibility settings
    @State private var reduceMotion = SettingsService.shared.reduceMotion
    @State private var highContrast = SettingsService.shared.highContrast
    @State private var largeTouchTargets = SettingsService.shared.largeTouchTargets

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
                        Text("Edit")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingDisplayName = viewModel.identity?.displayName ?? ""
                        showEditNameAlert = true
                    }

                    HStack {
                        Text("Public ID")
                        Spacer()
                        if let publicId = viewModel.identity?.publicId {
                            Text(String(publicId.prefix(16)) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
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

                // Sync section - Delivery Status
                Section("Message Delivery") {
                    NavigationLink(destination: DeliveryStatusView()) {
                        HStack {
                            Label("Delivery Status", systemImage: "paperplane.circle")
                            Spacer()
                            if viewModel.failedDeliveryCount > 0 {
                                Text("\(viewModel.failedDeliveryCount) failed")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // Privacy section
                Section("Privacy") {
                    NavigationLink(destination: LabelsView()) {
                        HStack {
                            Label("Visibility Labels", systemImage: "tag")
                            Spacer()
                            if !viewModel.visibilityLabels.isEmpty {
                                Text("\(viewModel.visibilityLabels.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
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

                // Content Updates section
                if viewModel.isContentUpdatesSupported() {
                    ContentUpdatesSection()
                }

                // Accessibility section
                Section {
                    Toggle(isOn: $reduceMotion) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reduce Motion")
                            Text("Minimize animations and transitions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: reduceMotion) { newValue in
                        SettingsService.shared.reduceMotion = newValue
                    }
                    .accessibilityIdentifier("settings.accessibility.reduceMotion")
                    .accessibilityHint("Supplements the system Reduce Motion setting")

                    Toggle(isOn: $highContrast) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("High Contrast")
                            Text("Increase color contrast for better visibility")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: highContrast) { newValue in
                        SettingsService.shared.highContrast = newValue
                    }
                    .accessibilityIdentifier("settings.accessibility.highContrast")
                    .accessibilityHint("Supplements the system Increase Contrast setting")

                    Toggle(isOn: $largeTouchTargets) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Large Touch Targets")
                            Text("Increase button and control sizes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: largeTouchTargets) { newValue in
                        SettingsService.shared.largeTouchTargets = newValue
                    }
                    .accessibilityIdentifier("settings.accessibility.largeTouchTargets")
                    .accessibilityHint("Makes buttons and controls larger for easier tapping")
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text("These settings supplement system accessibility features. You can also configure accessibility in iOS Settings.")
                }

                // Help & Support section
                Section("Help & Support") {
                    // Demo contact restore option
                    if let state = viewModel.demoContactState, !state.isActive {
                        Button(action: {
                            Task {
                                try? await viewModel.restoreDemoContact()
                            }
                        }) {
                            HStack {
                                Label("Show Demo Contact", systemImage: "lightbulb")
                                Spacer()
                                Text("Learn how updates work")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accessibilityIdentifier("settings.help.restoreDemo")
                    }

                    // Reset tips (aha moments)
                    Button(action: {
                        Task {
                            try? await viewModel.resetAhaMoments()
                        }
                    }) {
                        HStack {
                            Label("Reset Tips", systemImage: "arrow.counterclockwise")
                            Spacer()
                            let progress = viewModel.ahaMomentsProgress()
                            Text("\(progress.seen)/\(progress.total) seen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.help.resetTips")

                    Link(destination: URL(string: "https://vauchi.app/user-guide")!) {
                        HStack {
                            Label("User Guide", systemImage: "book")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://vauchi.app/faq")!) {
                        HStack {
                            Label("FAQ", systemImage: "questionmark.circle")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://github.com/vauchi/issues")!) {
                        HStack {
                            Label("Report Issue", systemImage: "exclamationmark.bubble")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://vauchi.app/privacy")!) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // About section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                        Text("\(version) (build \(build))")
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
            .alert("Edit Display Name", isPresented: $showEditNameAlert) {
                TextField("Display Name", text: $editingDisplayName)
                    .autocapitalization(.words)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    saveDisplayName()
                }
            } message: {
                Text("Enter your new display name. This is how contacts will see you.")
            }
            .onAppear {
                relayUrl = SettingsService.shared.relayUrl
                reduceMotion = SettingsService.shared.reduceMotion
                highContrast = SettingsService.shared.highContrast
                largeTouchTargets = SettingsService.shared.largeTouchTargets
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

    private func saveDisplayName() {
        let trimmed = editingDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != viewModel.identity?.displayName else { return }

        Task {
            do {
                try await viewModel.setDisplayName(trimmed)
            } catch {
                // Error handling - the view model will update on success
                print("Failed to update display name: \(error)")
            }
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
    @State private var passwordCheck: MobilePasswordCheck?

    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var canExport: Bool {
        passwordsMatch && (passwordCheck?.isAcceptable ?? false)
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
                            .onChange(of: password) { newValue in
                                if !newValue.isEmpty {
                                    passwordCheck = checkPasswordStrength(password: newValue)
                                } else {
                                    passwordCheck = nil
                                }
                            }
                        SecureField("Confirm Password", text: $confirmPassword)

                        // Password strength indicator
                        if !password.isEmpty, let check = passwordCheck {
                            PasswordStrengthIndicator(check: check)
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
                        .disabled(!canExport || isExporting)
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

// MARK: - Content Updates Section

/// Section for checking and applying content updates (social networks, locales, themes)
struct ContentUpdatesSection: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var updateStatus: MobileUpdateStatus?
    @State private var isChecking = false
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Section {
            // Status row
            HStack {
                Label("Content Updates", systemImage: "arrow.down.circle")
                Spacer()
                if isChecking || isApplying {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let status = updateStatus {
                    UpdateStatusBadge(status: status)
                }
            }

            // Check for updates button
            Button(action: checkForUpdates) {
                HStack {
                    Text("Check for Updates")
                    Spacer()
                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(isChecking || isApplying)

            // Apply updates button (only when updates available)
            if let status = updateStatus, hasUpdatesAvailable(status) {
                Button(action: applyUpdates) {
                    HStack {
                        Text("Apply Updates")
                        Spacer()
                        if isApplying {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .foregroundColor(.cyan)
                        }
                    }
                }
                .disabled(isChecking || isApplying)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Success message
            if let success = successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        } header: {
            Text("Content Updates")
        } footer: {
            Text("Updates include new social networks, localization improvements, and themes.")
        }
    }

    private func hasUpdatesAvailable(_ status: MobileUpdateStatus) -> Bool {
        switch status {
        case .updatesAvailable:
            return true
        default:
            return false
        }
    }

    private func checkForUpdates() {
        isChecking = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let status = try await viewModel.checkContentUpdates()
                await MainActor.run {
                    updateStatus = status
                    switch status {
                    case .upToDate:
                        successMessage = "Everything is up to date"
                    case .updatesAvailable(let types):
                        let typeNames = types.map { updateTypeName($0) }.joined(separator: ", ")
                        successMessage = "Updates available: \(typeNames)"
                    case .checkFailed(let error):
                        errorMessage = "Check failed: \(error)"
                    case .disabled:
                        errorMessage = "Content updates are disabled"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isChecking = false
            }
        }
    }

    private func applyUpdates() {
        isApplying = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let result = try await viewModel.applyContentUpdates()
                await MainActor.run {
                    switch result {
                    case .noUpdates:
                        successMessage = "No updates to apply"
                    case .applied(let applied, let failed):
                        if failed.isEmpty {
                            successMessage = "Applied \(applied.count) update(s)"
                        } else {
                            successMessage = "Applied \(applied.count), failed \(failed.count)"
                        }
                        // Reload social networks after applying updates
                        Task {
                            try? await viewModel.reloadSocialNetworks()
                        }
                    case .disabled:
                        errorMessage = "Content updates are disabled"
                    case .error(let error):
                        errorMessage = "Apply failed: \(error)"
                    }
                    // Reset status after applying
                    updateStatus = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isApplying = false
            }
        }
    }

    private func updateTypeName(_ type: MobileUpdateType) -> String {
        switch type {
        case .networks:
            return "Social Networks"
        case .locales:
            return "Languages"
        case .themes:
            return "Themes"
        case .help:
            return "Help Content"
        }
    }
}

/// Badge showing content update status
struct UpdateStatusBadge: View {
    let status: MobileUpdateStatus

    var body: some View {
        switch status {
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Up to date")
                    .foregroundColor(.green)
            }
            .font(.caption)
        case .updatesAvailable(let types):
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.cyan)
                Text("\(types.count) available")
                    .foregroundColor(.cyan)
            }
            .font(.caption)
        case .checkFailed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Error")
                    .foregroundColor(.orange)
            }
            .font(.caption)
        case .disabled:
            Text("Disabled")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Password Strength Indicator

/// Visual indicator for password strength using the vauchi-mobile checkPasswordStrength API
struct PasswordStrengthIndicator: View {
    let check: MobilePasswordCheck

    var strengthColor: Color {
        switch check.strength {
        case .tooWeak:
            return .red
        case .fair:
            return .orange
        case .strong:
            return .green
        case .veryStrong:
            return .green
        }
    }

    var filledSegments: Int {
        switch check.strength {
        case .tooWeak:
            return 1
        case .fair:
            return 2
        case .strong:
            return 3
        case .veryStrong:
            return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Strength bar
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < filledSegments ? strengthColor : strengthColor.opacity(0.2))
                        .frame(height: 4)
                }
            }

            // Strength description and status
            HStack {
                Text(check.description)
                    .font(.caption)
                    .foregroundColor(strengthColor)

                Spacer()

                if check.isAcceptable {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("OK")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }
            }

            // Feedback for weak passwords
            if !check.feedback.isEmpty {
                Text(check.feedback)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(VauchiViewModel())
}
