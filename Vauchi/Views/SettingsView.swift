// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SettingsView.swift
// Settings and backup view

import CoreUIModels
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import VauchiPlatform

/// Classify a backup-import failure.
///
/// TODO(ADR-044): Once the UniFFI bindings ship the new `MobileError`
/// variants (`wrongPassword`, `decryptFailed`, `invalidInput`, `other`,
/// etc.), replace this substring match with a `switch` on the variant.
/// See `_private/docs/decisions/2026-04-20-adr-044-mobile-error-typing.md`.
private func classifyBackupImportError(_ error: Error) -> String {
    let description = error.localizedDescription
    if description.contains("decrypt") || description.contains("password") {
        return "Incorrect password"
    }
    return description
}

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

    @State private var showPanicShredConfirm = false
    @State private var showScheduleShredConfirm = false
    @State private var showExecuteShredConfirm = false
    @State private var shredMessage = ""

    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            List {
                #if DEBUG
                    // Diagnostics (debug builds only)
                    Section("Diagnostics") {
                        NavigationLink("QR Diagnostic") {
                            QRDiagnosticView(autoTest: nil)
                        }
                        NavigationLink("BLE Diagnostic") {
                            BleDiagnosticView(autoTest: nil, autoMode: nil)
                        }
                        NavigationLink("QR Camera Tuner") {
                            QrCameraTunerView(autoTest: nil)
                        }
                        NavigationLink("Ultrasonic Diagnostic") {
                            DiagnosticView()
                        }
                        NavigationLink("NFC Diagnostic") {
                            NfcDiagnosticView(autoTest: nil)
                        }
                        NavigationLink(destination: NfcTestView()) {
                            Label("NFC Exchange Test", systemImage: "wave.3.right")
                        }
                    }
                #endif

                // Identity section
                Section(localizationService.t("settings.identity")) {
                    HStack {
                        Text(localizationService.t("settings.display_name"))
                        Spacer()
                        Text(viewModel.displayName ?? "Unknown")
                            .foregroundColor(.secondary)
                        Text(localizationService.t("action.edit"))
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingDisplayName = viewModel.displayName ?? ""
                        showEditNameAlert = true
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localizationService.t("settings.display_name"))
                    .accessibilityValue(viewModel.displayName ?? "Unknown")
                    .accessibilityHint("Double tap to edit your display name")
                    .accessibilityAddTraits(.isButton)

                    HStack {
                        Text(localizationService.t("home.public_id"))
                        Spacer()
                        if let publicId = viewModel.publicId {
                            Text(String(publicId.prefix(16)) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localizationService.t("home.public_id"))
                    .accessibilityValue(viewModel.publicId ?? "Unknown")
                    .accessibilityHint("Long press to copy full public ID")
                    .contextMenu {
                        if let publicId = viewModel.publicId {
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
                        Text(localizationService.t("settings.relay"))
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localizationService.t("settings.relay"))
                    .accessibilityValue(relayUrl)
                    .accessibilityHint("Double tap to edit the relay server URL")
                    .accessibilityAddTraits(.isButton)

                    Button(action: { Task { await viewModel.sync() } }) {
                        HStack {
                            Label(localizationService.t("sync.title"), systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            SyncStatusBadge(state: viewModel.syncState)
                        }
                    }
                    .disabled(viewModel.syncState == .syncing)
                    .accessibilityLabel("Sync now")
                    .accessibilityHint("Synchronize your card and contacts with the relay server")

                    if let lastSync = viewModel.lastSyncTime {
                        HStack {
                            Text(localizationService.t("sync.last_sync"))
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
                    Text(localizationService.t("sync.title"))
                } footer: {
                    Text("Sync keeps your contacts up to date across devices.")
                }

                // Backup section
                Section {
                    Button(action: { showExportSheet = true }) {
                        Label(localizationService.t("backup.export"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel(localizationService.t("backup.export"))
                    .accessibilityHint("Opens the backup export sheet to save your identity")

                    Button(action: { showImportSheet = true }) {
                        Label(localizationService.t("backup.import"), systemImage: "square.and.arrow.down")
                    }
                    .accessibilityLabel(localizationService.t("backup.import"))
                    .accessibilityHint("Opens the backup import sheet to restore an identity")
                } header: {
                    Text(localizationService.t("backup.title"))
                } footer: {
                    Text("Back up your identity, contacts, and labels to restore on another device or after reinstalling.")
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
                    .accessibilityHint("View the delivery status of your card updates")
                }

                // Privacy section
                Section(localizationService.t("settings.privacy")) {
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
                    .accessibilityHint("Manage labels that control which fields contacts can see")

                    NavigationLink(destination: GroupsView()) {
                        HStack {
                            Label("Contact Groups", systemImage: "person.3")
                            Spacer()
                            if !viewModel.visibilityLabels.isEmpty {
                                Text("\(viewModel.visibilityLabels.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Manage contact groups and their visibility settings")

                    NavigationLink(destination: SocialGraphView()) {
                        Label("Contact Network", systemImage: "network")
                    }
                    .accessibilityHint("View your contact network with trust levels and group memberships")

                    NavigationLink(destination: ConsentSettingsView()) {
                        Label("Consent Settings", systemImage: "hand.raised")
                    }
                    .accessibilityHint("Manage your data processing and sharing consent preferences")

                    NavigationLink(destination: AccountDeletionView()) {
                        Label("Delete Identity", systemImage: "trash.circle")
                    }
                    .accessibilityHint("Schedule or cancel deletion of your account")

                    Button(action: exportGdprData) {
                        Label("Export My Data", systemImage: "square.and.arrow.up.on.square")
                    }
                    .accessibilityHint("Download a copy of all your personal data")

                    switch viewModel.shredStatus {
                    case .none:
                        Button(role: .destructive) {
                            showScheduleShredConfirm = true
                        } label: {
                            Label("Schedule Deletion (7-day)", systemImage: "clock.badge.xmark")
                        }
                        .accessibilityHint("Schedule data destruction with a 7-day grace period")
                    case let .scheduled(remainingSecs):
                        let days = remainingSecs / 86400
                        let hours = (remainingSecs % 86400) / 3600
                        HStack {
                            Label("Deletion in \(days)d \(hours)h", systemImage: "clock.badge.xmark")
                                .foregroundColor(.red)
                            Spacer()
                        }
                        Button("Cancel Deletion") {
                            Task {
                                try? await viewModel.cancelScheduledShred()
                            }
                        }
                        if remainingSecs == 0 {
                            Button(role: .destructive) {
                                showExecuteShredConfirm = true
                            } label: {
                                Label("Execute Deletion Now", systemImage: "trash.fill")
                            }
                        }
                    case .executed:
                        Text("All data has been permanently destroyed.")
                            .foregroundColor(.red)
                    }

                    Button(role: .destructive) {
                        showPanicShredConfirm = true
                    } label: {
                        Label("Emergency Shred", systemImage: "exclamationmark.shield")
                    }
                    .accessibilityLabel("Emergency Shred")
                    .accessibilityHint("Irreversibly destroys all data including contacts, identity, and encryption keys")
                }

                // Security section
                Section("Security") {
                    NavigationLink(destination: LinkedDevicesView()) {
                        Label(localizationService.t("devices.linked"), systemImage: "laptopcomputer.and.iphone")
                    }
                    .accessibilityHint("Manage devices linked to your identity")

                    NavigationLink(destination: RecoveryView()) {
                        Label(localizationService.t("recovery.title"), systemImage: "person.badge.key")
                    }
                    .accessibilityHint("Set up or manage social recovery for your identity")

                    NavigationLink(destination: CertificatePinningView()) {
                        HStack {
                            Label("Certificate Pinning", systemImage: "lock.shield")
                            Spacer()
                            if viewModel.isCertificatePinningEnabled() {
                                Text("Enabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Pin a specific TLS certificate for the relay server")

                    NavigationLink(destination: DuressSettingsView()) {
                        HStack {
                            Label("Duress PIN", systemImage: "shield.lefthalf.filled")
                            Spacer()
                            if viewModel.isDuressEnabled {
                                Text("Enabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Configure a duress PIN that wipes data when entered under threat")

                    NavigationLink(destination: EmergencyBroadcastView()) {
                        HStack {
                            Label("Emergency Broadcast", systemImage: "megaphone")
                            Spacer()
                            if viewModel.emergencyConfigured {
                                Text("Configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Configure emergency alerts sent to trusted contacts")
                }

                // Content Updates section
                if viewModel.isContentUpdatesSupported() {
                    ContentUpdatesSection()
                }

                // Appearance section
                Section(localizationService.t("settings.appearance")) {
                    NavigationLink(destination: ThemeSettingsView()) {
                        HStack {
                            Label(localizationService.t("settings.theme"), systemImage: "paintpalette")
                            Spacer()
                            if let theme = ThemeService.shared.currentTheme {
                                Text(theme.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.appearance.theme")
                    .accessibilityHint("Choose a visual theme for the app")

                    NavigationLink(destination: LanguageSettingsView()) {
                        HStack {
                            Label(localizationService.t("settings.language"), systemImage: "globe")
                            Spacer()
                            Text(LocalizationService.shared.currentLocaleInfo.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance.language")
                    .accessibilityHint("Change the app display language")
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
                Section(localizationService.t("settings.help_support")) {
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
                        .accessibilityHint("Restores the demo contact to show how card updates work")
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
                    .accessibilityHint("Resets all in-app tips so you can see them again")

                    Link(destination: URL(string: "https://vauchi.app/user-guide")!) {
                        HStack {
                            Label("User Guide", systemImage: "book")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint("Opens the online user guide in your browser")

                    NavigationLink(destination: HelpView()) {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.help.faq")
                    .accessibilityHint("View frequently asked questions and troubleshooting")

                    Link(destination: URL(string: "https://github.com/vauchi/issues")!) {
                        HStack {
                            Label("Report Issue", systemImage: "exclamationmark.bubble")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint("Opens the issue tracker in your browser to report a bug")

                    Link(destination: URL(string: "https://vauchi.app/privacy")!) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint("Opens the privacy policy in your browser")
                }

                // Support section
                Section(localizationService.t("support.title")) {
                    Text(localizationService.t("support.description"))
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://github.com/sponsors/vauchi")!) {
                        HStack {
                            Label(localizationService.t("support.github_sponsors"), systemImage: "heart")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }

                    Link(destination: URL(string: "https://liberapay.com/Vauchi/donate")!) {
                        HStack {
                            Label(localizationService.t("support.liberapay"), systemImage: "heart")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }

                // About section
                Section(localizationService.t("settings.about")) {
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
                                .accessibilityHidden(true)
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
            .navigationTitle(localizationService.t("nav.settings"))
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
                Button(localizationService.t("action.cancel"), role: .cancel) {}
                Button(localizationService.t("action.save")) {
                    saveRelayUrl()
                }
            } message: {
                Text("Enter the URL of your relay server (https://).")
            }
            .alert("Invalid URL", isPresented: $showInvalidUrlAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid relay URL starting with https://. Unencrypted connections (http://) are only allowed for localhost.")
            }
            .alert("Edit Display Name", isPresented: $showEditNameAlert) {
                TextField("Display Name", text: $editingDisplayName)
                    .autocapitalization(.words)
                Button(localizationService.t("action.cancel"), role: .cancel) {}
                Button(localizationService.t("action.save")) {
                    saveDisplayName()
                }
            } message: {
                Text("Enter your new display name. This is how contacts will see you.")
            }
            .alert("Emergency Shred", isPresented: $showPanicShredConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Destroy All Data", role: .destructive) {
                    Task {
                        await viewModel.panicShred()
                        shredMessage = "All data destroyed."
                    }
                }
            } message: {
                Text("This will immediately and irreversibly destroy all data including contacts, identity, and encryption keys. This cannot be undone.")
            }
            .alert("Schedule Deletion", isPresented: $showScheduleShredConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Schedule", role: .destructive) {
                    Task { try? await viewModel.scheduleSoftShred() }
                }
            } message: {
                Text("This starts a 7-day countdown. After the grace period, all data will be irreversibly destroyed. You can cancel during the grace period.")
            }
            .alert("Execute Deletion", isPresented: $showExecuteShredConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Destroy Everything", role: .destructive) {
                    Task { try? await viewModel.executeHardShred() }
                }
            } message: {
                Text("This will permanently destroy ALL data including your identity, contacts, and encryption keys. This cannot be undone.")
            }
            .task {
                await viewModel.loadShredStatus()
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
        guard trimmed != viewModel.displayName else { return }

        Task {
            do {
                try await viewModel.setDisplayName(trimmed)
            } catch {
                // Error handling - the view model will update on success
                #if DEBUG
                    print("Failed to update display name: \(error)")
                #endif
            }
        }
    }

    private func exportGdprData() {
        Task {
            do {
                let export = try await viewModel.exportGdprData()
                // Share the exported JSON data
                let tempDir = FileManager.default.temporaryDirectory
                let fileUrl = tempDir.appendingPathComponent("vauchi-data-export.json")
                try export.jsonData.write(to: fileUrl, atomically: true, encoding: .utf8)

                await MainActor.run {
                    let activityController = UIActivityViewController(
                        activityItems: [fileUrl],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(activityController, animated: true)
                    }
                }
            } catch {
                viewModel.showError("Export Failed", message: error.localizedDescription)
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
                .accessibilityLabel("Syncing")
        case let .success(added, updated, sent, names):
            let label = if !names.isEmpty {
                LocalizationService.shared.t("sync.updated_contacts", args: ["names": names.joined(separator: ", ")])
            } else if added + updated + sent > 0 {
                "\(added + updated + sent) changes"
            } else {
                "Up to date"
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .accessibilityLabel("Sync error")
        }
    }
}

struct LinkedDevicesView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var devices: [VauchiRepository.DeviceInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showLinkSheet = false
    @State private var showUnlinkConfirmation = false
    @State private var deviceToUnlink: VauchiRepository.DeviceInfo?
    @State private var isPrimary = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            } else {
                // Devices list
                Section {
                    ForEach(devices) { device in
                        DeviceRow(device: device, onUnlink: {
                            deviceToUnlink = device
                            showUnlinkConfirmation = true
                        })
                    }
                } header: {
                    Text("Devices (\(devices.count))")
                } footer: {
                    if isPrimary {
                        Text("This is the primary device. You can link additional devices to access your identity from multiple places.")
                    } else {
                        Text("This device is linked to your primary identity.")
                    }
                }

                // Link new device button
                Section {
                    Button(action: { showLinkSheet = true }) {
                        Label("Link New Device", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Generate a QR code on this device for a new device to scan.")
                }
            }
        }
        .navigationTitle("Linked Devices")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadDevices()
            }
        }
        .refreshable {
            await loadDevices()
        }
        .sheet(isPresented: $showLinkSheet) {
            DeviceLinkSheet()
        }
        .alert("Unlink Device?", isPresented: $showUnlinkConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unlink", role: .destructive) {
                if let device = deviceToUnlink {
                    Task {
                        await unlinkDevice(device)
                    }
                }
            }
        } message: {
            if let device = deviceToUnlink {
                Text("This will remove \"\(device.deviceName)\" from your linked devices. The device will no longer have access to your identity.")
            }
        }
    }

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            devices = try await viewModel.getDevices()
            isPrimary = try await viewModel.isPrimaryDevice()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func unlinkDevice(_ device: VauchiRepository.DeviceInfo) async {
        do {
            let success = try await viewModel.unlinkDevice(deviceIndex: device.deviceIndex)
            if success {
                await loadDevices()
            } else {
                errorMessage = "Failed to unlink device"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Row displaying a single device
struct DeviceRow: View {
    let device: VauchiRepository.DeviceInfo
    let onUnlink: () -> Void

    var deviceIcon: String {
        let deviceType = classifyDeviceType(name: device.deviceName)
        switch deviceType {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .laptop: return "laptopcomputer"
        case .watch: return "applewatch"
        case .desktop: return "desktopcomputer"
        case .unknown: return "desktopcomputer"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: deviceIcon)
                .foregroundColor(.cyan)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(device.deviceName)
                        .font(.body)
                    if device.isCurrent {
                        Text("(This device)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(device.publicKeyPrefix)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)

                    if !device.isActive {
                        Text("Inactive")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if device.isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Current device")
            } else {
                // Unlink button for non-current devices
                Button(action: onUnlink) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlink \(device.deviceName)")
                .accessibilityHint("Removes this device from your linked devices")
            }
        }
        .contextMenu {
            if !device.isCurrent {
                Button(role: .destructive, action: onUnlink) {
                    Label("Unlink Device", systemImage: "trash")
                }
            }

            Button(action: {
                UIPasteboard.general.string = device.publicKeyPrefix
            }) {
                Label("Copy Device ID", systemImage: "doc.on.doc")
            }
        }
    }
}

/// Transport selection for device linking
enum DeviceLinkTransport {
    case notSelected
    case internet // existing relay flow
    case offline // multipart QR flow (stub)
}

/// Sheet for device linking full protocol flow
struct DeviceLinkSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.designTokens) private var tokens
    @State private var qrData: String?
    @State private var isListening = false
    @State private var transport: DeviceLinkTransport = .notSelected

    var body: some View {
        NavigationView {
            Group {
                switch transport {
                case .notSelected:
                    transportSelectionView

                case .offline:
                    offlineStubView

                case .internet:
                    internetFlowView
                }
            }
            .padding()
            .navigationTitle("Link New Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelDeviceLink()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                if case .success = viewModel.deviceLinkState {
                    viewModel.cancelDeviceLink()
                } else if case .idle = viewModel.deviceLinkState {
                    // already cleaned up
                } else {
                    viewModel.cancelDeviceLink()
                }
            }
        }
    }

    // MARK: - Transport Selection

    private var transportSelectionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.cyan)
                .accessibilityHidden(true)

            Text("How would you like to link?")
                .font(Font.title3.weight(.semibold))

            Text("Choose how to connect with your new device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: {
                    transport = .internet
                    startLinkFlow()
                }) {
                    Label("Link via Internet", systemImage: "wifi")
                        .font(Font.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                }
                .accessibilityHint("Links devices using the relay server over the internet")

                Button(action: {
                    transport = .offline
                }) {
                    Label("Link Offline (QR)", systemImage: "qrcode")
                        .font(Font.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                }
                .accessibilityHint("Links devices using animated QR codes without internet")
            }
        }
    }

    // MARK: - Offline Stub

    private var offlineStubView: some View {
        VStack(spacing: 24) {
            Image(systemName: "qrcode")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("Offline Device Linking")
                .font(Font.title3.weight(.semibold))

            Text("Coming soon — offline device linking requires protocol updates.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("This mode will use animated QR codes to exchange device linking data without requiring an internet connection.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                transport = .notSelected
            }) {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
        }
    }

    // MARK: - Internet Flow (existing relay flow)

    private var internetFlowView: some View {
        Group {
            switch viewModel.deviceLinkState {
            case .idle, .generatingQR:
                VStack(spacing: 20) {
                    ProgressView("Generating link...")
                }

            case let .waitingForRequest(expiresAt):
                waitingForRequestView(expiresAt: expiresAt)

            case .expired:
                expiredQRView

            case let .confirmingDevice(name, code, challenge):
                confirmingDeviceView(name: name, code: code, challenge: challenge)

            case let .verifyingProximity(challenge, confirmationCode):
                ProximityVerificationView(
                    challenge: challenge,
                    confirmationCode: confirmationCode,
                    onVerified: { result in
                        Task {
                            do {
                                let now = UInt64(Date().timeIntervalSince1970)
                                switch result {
                                case let .ultrasonic(challengeResponse):
                                    try await viewModel.approveDeviceLinkUltrasonic(
                                        challengeResponse: challengeResponse,
                                        verifiedAt: now
                                    )
                                case let .manual(code):
                                    try await viewModel.approveDeviceLinkManual(
                                        confirmationCode: code,
                                        confirmedAt: now
                                    )
                                }
                            } catch {
                                viewModel.deviceLinkState = .failed(error.localizedDescription)
                            }
                        }
                    },
                    onCancel: {
                        viewModel.cancelDeviceLink()
                        dismiss()
                    }
                )

            case .completing:
                VStack(spacing: 20) {
                    ProgressView("Completing link...")
                    Text("Sending credentials to new device...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .success:
                successView

            case let .failed(message):
                failedView(message: message)
            }
        }
    }

    // MARK: - Subviews

    private func waitingForRequestView(expiresAt: UInt64) -> some View {
        QRCountdownView(
            qrData: qrData,
            expiresAt: expiresAt,
            generateQRCode: generateQRCode,
            onExpired: { viewModel.deviceLinkState = .expired }
        )
    }

    private var expiredQRView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundColor(.orange)

            Text("QR Code Expired")
                .font(Font.title2.weight(.semibold))

            Text("The device link QR code has expired for security reasons. Generate a new one to continue.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                viewModel.cancelDeviceLink()
                startLinkFlow()
            }) {
                Text("Generate New QR")
                    .font(Font.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
            .accessibilityHint("Generates a new device link QR code")
            .padding(.horizontal)
        }
    }

    private func confirmingDeviceView(name: String, code: String, challenge: Data) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 48))
                .foregroundColor(.cyan)
                .accessibilityHidden(true)

            Text("Device Wants to Link")
                .font(Font.title2.weight(.semibold))

            VStack(spacing: 8) {
                Text("Device: **\(name)**")
                    .font(.body)

                Text("Confirmation Code")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(code)
                    .font(Font.system(.title, design: .monospaced).weight(.bold))
                    .foregroundColor(.cyan)
                    .accessibilityLabel("Confirmation code: \(code)")
            }

            Text("Verify this code matches the code shown on the new device, then proceed to proximity verification.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer().frame(height: 8)

            Button(action: {
                viewModel.deviceLinkState = .verifyingProximity(challenge: challenge, confirmationCode: code)
            }) {
                Text("Codes Match — Verify Proximity")
                    .font(Font.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
            .accessibilityHint("Proceeds to proximity verification step")

            Button(action: {
                viewModel.cancelDeviceLink()
                dismiss()
            }) {
                Text("Deny")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
            }
            .accessibilityHint("Rejects the device link request")
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Device Linked Successfully")
                .font(Font.title2.weight(.semibold))

            Text("The new device now has access to your identity. You can manage linked devices in Settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                viewModel.cancelDeviceLink()
                dismiss()
            }
            .font(Font.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.cyan)
            .foregroundColor(.white)
            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(.red)
                .accessibilityHidden(true)

            Text("Linking Failed")
                .font(Font.title2.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                viewModel.cancelDeviceLink()
                startLinkFlow()
            }
            .font(Font.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.cyan)
            .foregroundColor(.white)
            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

            Button("Cancel") {
                viewModel.cancelDeviceLink()
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray5))
            .foregroundColor(.primary)
            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        }
    }

    // MARK: - Flow Control

    private func startLinkFlow() {
        Task {
            do {
                let data = try await viewModel.startDeviceLinkInitiator()
                qrData = data

                // Start listening for incoming request in background
                try await viewModel.listenForDeviceLinkRequest()
            } catch {
                viewModel.deviceLinkState = .failed(error.localizedDescription)
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let qr = try? generateQrBitmap(
            data: string, size: 512, ecc: .high, dark: 0, light: 255, margin: 4
        ) else { return nil }
        let imageSize = Int(qr.size)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(qr.pixels) as CFData),
              let cgImage = CGImage(
                  width: imageSize, height: imageSize,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: imageSize,
                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct CertificatePinningView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var certificatePem = ""
    @State private var showPasteSheet = false
    @State private var showClearConfirmation = false

    var isPinningEnabled: Bool {
        viewModel.isCertificatePinningEnabled()
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Status", systemImage: isPinningEnabled ? "lock.shield.fill" : "lock.shield")
                    Spacer()
                    Text(isPinningEnabled ? "Enabled" : "Disabled")
                        .foregroundStyle(isPinningEnabled ? .primary : .secondary)
                }
            } header: {
                Text("Certificate Pinning")
            } footer: {
                Text("Certificate pinning ensures the app only connects to relay servers presenting a specific certificate, preventing man-in-the-middle attacks.")
            }

            Section {
                Button(action: { showPasteSheet = true }) {
                    Label("Set Certificate", systemImage: "doc.badge.plus")
                }
                .accessibilityLabel("Set Certificate")
                .accessibilityHint("Opens a sheet to paste a PEM certificate for pinning")

                if isPinningEnabled {
                    Button(role: .destructive, action: { showClearConfirmation = true }) {
                        Label("Clear Certificate", systemImage: "trash")
                    }
                    .accessibilityLabel("Clear Certificate")
                    .accessibilityHint("Removes the pinned certificate and allows connections to any valid relay server")
                }
            } header: {
                Text("Actions")
            } footer: {
                if isPinningEnabled {
                    Text("Warning: Clearing the certificate will allow connections to any valid relay server.")
                } else {
                    Text("Paste a certificate in PEM format to enable pinning. This is typically provided by your organization's IT department.")
                }
            }
        }
        .navigationTitle("Certificate Pinning")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPasteSheet) {
            SetCertificateSheet(onSet: { certPem in
                viewModel.setPinnedCertificate(certPem)
            })
        }
        .alert("Clear Certificate?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.setPinnedCertificate("")
            }
        } message: {
            Text("This will disable certificate pinning and allow connections to any valid relay server.")
        }
    }
}

struct SetCertificateSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSet: (String) -> Void

    @State private var certificateText = ""
    @State private var errorMessage: String?

    var isValidPem: Bool {
        let trimmed = certificateText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("-----BEGIN CERTIFICATE-----") &&
            trimmed.hasSuffix("-----END CERTIFICATE-----")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextEditor(text: $certificateText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                } header: {
                    Text("Certificate (PEM Format)")
                } footer: {
                    Text("Paste the certificate provided by your organization. It should begin with '-----BEGIN CERTIFICATE-----'.")
                }

                if !certificateText.isEmpty, !isValidPem {
                    Section {
                        Text("Invalid PEM format. Certificate must begin with '-----BEGIN CERTIFICATE-----' and end with '-----END CERTIFICATE-----'.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: {
                        onSet(certificateText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("Set Certificate")
                            Spacer()
                        }
                    }
                    .disabled(!isValidPem)
                }
            }
            .navigationTitle("Set Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ExportBackupSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.designTokens) private var tokens
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
                        .accessibilityHidden(true)

                    Text("Authentication Required")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)

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
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .padding(.horizontal)
                    .accessibilityHint("Use Face ID or Touch ID to verify your identity before exporting")

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

                        if !password.isEmpty, !confirmPassword.isEmpty, !passwordsMatch {
                            Text("Passwords don't match")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } header: {
                        Text("Encrypt Backup")
                    } footer: {
                        Text("Your backup will be encrypted with this password. It includes your identity, contacts, and labels. Store it safely.")
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
                let backup = try await viewModel.exportFullBackup(password: password)
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

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

struct ImportBackupSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.designTokens) private var tokens
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
                        .accessibilityHidden(true)

                    Text("Authentication Required")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)

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
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .padding(.horizontal)
                    .accessibilityHint("Use Face ID or Touch ID to verify your identity before importing")

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
                        .accessibilityHidden(true)

                    Text("Import Backup")
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)

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
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text("Backup file loaded")
                            }
                            .accessibilityElement(children: .combine)

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
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
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
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
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
                    Button("Cancel", role: .cancel) {}
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
        case let .success(urls):
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
        case let .failure(error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        guard let data = backupData else { return }

        isImporting = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.importFullBackup(data: data, password: password)
                dismiss()
            } catch {
                errorMessage = classifyBackupImportError(error)
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
                    .foregroundStyle(.secondary)
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
            true
        default:
            false
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
                    case let .updatesAvailable(types):
                        let typeNames = types.map { updateTypeName($0) }.joined(separator: ", ")
                        successMessage = "Updates available: \(typeNames)"
                    case let .checkFailed(error):
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
                    case let .applied(applied, failed):
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
                    case let .error(error):
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

    private func updateTypeName(_ type: MobileContentType) -> String {
        switch type {
        case .networks:
            "Social Networks"
        case .locales:
            "Languages"
        case .themes:
            "Themes"
        case .help:
            "Help Content"
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
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Up to date")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Content updates: up to date")
        case let .updatesAvailable(types):
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.cyan)
                    .accessibilityHidden(true)
                Text("\(types.count) available")
                    .foregroundColor(.cyan)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Content updates: \(types.count) available")
        case .checkFailed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text("Error")
                    .foregroundColor(.orange)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Content updates: error checking for updates")
        case .disabled:
            Text("Disabled")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Password Strength Indicator

/// Visual indicator for password strength using the vauchi-platform checkPasswordStrength API
struct PasswordStrengthIndicator: View {
    let check: MobilePasswordCheck

    var strengthColor: Color {
        switch check.strength {
        case .tooWeak:
            .red
        case .fair:
            .orange
        case .strong:
            .green
        case .veryStrong:
            .green
        }
    }

    var filledSegments: Int {
        switch check.strength {
        case .tooWeak:
            1
        case .fair:
            2
        case .strong:
            3
        case .veryStrong:
            4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Strength bar
            HStack(spacing: 4) {
                ForEach(0 ..< 4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < filledSegments ? strengthColor : strengthColor.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)

            // Strength description and status
            HStack {
                Text(check.description)
                    .font(.caption)
                    .foregroundColor(strengthColor)

                Spacer()

                if check.isAcceptable {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("OK")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityLabel("Password strength acceptable")
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
