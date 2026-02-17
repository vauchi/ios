// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SettingsView.swift
// Settings and backup view

import CoreImage.CIFilterBuiltins
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import VauchiMobile

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
    @State private var shredMessage = ""

    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            List {
                // Identity section
                Section(localizationService.t("settings.identity")) {
                    HStack {
                        Text(localizationService.t("settings.display_name"))
                        Spacer()
                        Text(viewModel.identity?.displayName ?? "Unknown")
                            .foregroundColor(.secondary)
                        Text(localizationService.t("action.edit"))
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingDisplayName = viewModel.identity?.displayName ?? ""
                        showEditNameAlert = true
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localizationService.t("settings.display_name"))
                    .accessibilityValue(viewModel.identity?.displayName ?? "Unknown")
                    .accessibilityHint("Double tap to edit your display name")
                    .accessibilityAddTraits(.isButton)

                    HStack {
                        Text(localizationService.t("home.public_id"))
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localizationService.t("home.public_id"))
                    .accessibilityValue(viewModel.identity?.publicId ?? "Unknown")
                    .accessibilityHint("Long press to copy full public ID")
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

                    Button(action: { Task { await viewModel.sync() } }) {
                        HStack {
                            Label(localizationService.t("sync.title"), systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            SyncStatusBadge(state: viewModel.syncState)
                        }
                    }
                    .disabled(viewModel.syncState == .syncing)

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

                    NavigationLink(destination: ConsentSettingsView()) {
                        Label("Consent Settings", systemImage: "hand.raised")
                    }

                    NavigationLink(destination: AccountDeletionView()) {
                        Label("Account Deletion", systemImage: "trash.circle")
                    }

                    Button(action: exportGdprData) {
                        Label("Export My Data", systemImage: "square.and.arrow.up.on.square")
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

                    NavigationLink(destination: RecoveryView()) {
                        Label(localizationService.t("recovery.title"), systemImage: "person.badge.key")
                    }

                    NavigationLink(destination: CertificatePinningView()) {
                        HStack {
                            Label("Certificate Pinning", systemImage: "lock.shield")
                            Spacer()
                            if viewModel.isCertificatePinningEnabled() {
                                Text("Enabled")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    NavigationLink(destination: DuressSettingsView()) {
                        HStack {
                            Label("Duress PIN", systemImage: "shield.lefthalf.filled")
                            Spacer()
                            if viewModel.isDuressEnabled {
                                Text("Enabled")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    NavigationLink(destination: EmergencyBroadcastView()) {
                        HStack {
                            Label("Emergency Broadcast", systemImage: "megaphone")
                            Spacer()
                            if viewModel.emergencyConfigured {
                                Text("Configured")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    NavigationLink(destination: TorSettingsView()) {
                        HStack {
                            Label("Tor Mode", systemImage: "network.badge.shield.half.filled")
                            Spacer()
                            if viewModel.isTorEnabled {
                                Text("Enabled")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
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
                                .accessibilityHidden(true)
                        }
                    }

                    NavigationLink(destination: HelpView()) {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.help.faq")

                    Link(destination: URL(string: "https://github.com/vauchi/issues")!) {
                        HStack {
                            Label("Report Issue", systemImage: "exclamationmark.bubble")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                        }
                    }

                    Link(destination: URL(string: "https://vauchi.app/privacy")!) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised")
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
                Text("Enter the secure WebSocket URL of your relay server (wss://).")
            }
            .alert("Invalid URL", isPresented: $showInvalidUrlAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid secure WebSocket URL starting with wss://. Unencrypted connections (ws://) are not allowed for security.")
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
                       let rootViewController = windowScene.windows.first?.rootViewController
                    {
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
        case let .success(added, updated, sent):
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
        // Simple heuristic based on device name
        let name = device.deviceName.lowercased()
        if name.contains("iphone") {
            return "iphone"
        } else if name.contains("ipad") {
            return "ipad"
        } else if name.contains("mac") {
            return "laptopcomputer"
        } else if name.contains("watch") {
            return "applewatch"
        } else {
            return "desktopcomputer"
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
                    .foregroundColor(.green)
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

/// Sheet for generating device link QR code
struct DeviceLinkSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.dismiss) var dismiss
    @State private var linkData: VauchiRepository.DeviceLinkData?
    @State private var isGenerating = true
    @State private var errorMessage: String?
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isGenerating {
                    ProgressView("Generating link...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task {
                                await generateLinkQr()
                            }
                        }
                        .accessibilityHint("Attempts to generate a new device link QR code")
                    }
                } else if let data = linkData {
                    VStack(spacing: 16) {
                        Text("Scan this QR code on your new device")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        // QR Code
                        if let qrImage = generateQRCode(from: data.qrData) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .accessibilityLabel("Device link QR code")
                                .accessibilityHint("Show this QR code to the new device to scan")
                        }

                        // Expiry timer
                        if timeRemaining > 0 {
                            HStack {
                                Image(systemName: "clock")
                                    .accessibilityHidden(true)
                                Text("Expires in \(formatTime(timeRemaining))")
                            }
                            .font(.caption)
                            .foregroundColor(timeRemaining < 60 ? .orange : .secondary)
                            .accessibilityElement(children: .combine)
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .accessibilityHidden(true)
                                Text("QR code expired")
                            }
                            .font(.caption)
                            .foregroundColor(.red)

                            Button("Generate New Code") {
                                Task {
                                    await generateLinkQr()
                                }
                            }
                        }

                        Text("Open Vauchi on your new device and select \"Join Existing Identity\" to scan this code.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Link New Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                Task {
                    await generateLinkQr()
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }

    private func generateLinkQr() async {
        isGenerating = true
        errorMessage = nil
        timer?.invalidate()

        do {
            linkData = try await viewModel.generateDeviceLinkQr()
            timeRemaining = linkData?.timeRemaining ?? 0
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }

        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")

            if let output = filter.outputImage {
                let transform = CGAffineTransform(scaleX: 10, y: 10)
                let scaled = output.transformed(by: transform)
                return UIImage(ciImage: scaled)
            }
        }
        return nil
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
                        .foregroundColor(isPinningEnabled ? .green : .secondary)
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

struct DuressSettingsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showPasswordSetup = false
    @State private var showDuressSetup = false
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
                        .foregroundColor(viewModel.isPasswordEnabled ? .green : .secondary)
                }

                HStack {
                    Label("Duress PIN", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    Text(viewModel.isDuressEnabled ? "Enabled" : "Not set")
                        .foregroundColor(viewModel.isDuressEnabled ? .green : .secondary)
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

            if !successMessage.isEmpty {
                Section {
                    Text(successMessage)
                        .foregroundColor(.green)
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
                guard password.count >= 4 else {
                    errorMessage = "Password must be at least 4 characters"
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
                guard duressPin.count >= 4 else {
                    errorMessage = "PIN must be at least 4 characters"
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
    }
}

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
                        .foregroundColor(viewModel.emergencyConfigured ? .green : .secondary)
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
                Section { Text(successMessage).foregroundColor(.green) }
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

                if !certificateText.isEmpty && !isValidPem {
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

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
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
                try await viewModel.importBackup(data: data, password: password)
                dismiss()
            } catch {
                if error.localizedDescription.contains("decrypt") ||
                    error.localizedDescription.contains("password")
                {
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
        case let .updatesAvailable(types):
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
                ForEach(0 ..< 4, id: \.self) { index in
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

// MARK: - Tor Settings View

struct TorSettingsView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var torEnabled: Bool = false
    @State private var preferOnion: Bool = true
    @State private var bridgeText: String = ""
    @State private var showAddBridge: Bool = false
    @State private var newBridge: String = ""
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""

    var body: some View {
        List {
            Section {
                Toggle("Enable Tor", isOn: $torEnabled)
                    .onChange(of: torEnabled) { newValue in
                        let bridges = bridgeText.split(separator: "\n").map(String.init)
                        viewModel.saveTorConfig(enabled: newValue, bridges: bridges, preferOnion: preferOnion)
                    }
                    .accessibilityLabel("Enable Tor")
                    .accessibilityHint("Routes all relay traffic through the Tor network for enhanced anonymity")

                Toggle("Prefer .onion Addresses", isOn: $preferOnion)
                    .onChange(of: preferOnion) { newValue in
                        let bridges = bridgeText.split(separator: "\n").map(String.init)
                        viewModel.saveTorConfig(enabled: torEnabled, bridges: bridges, preferOnion: newValue)
                    }
                    .accessibilityLabel("Prefer onion addresses")
                    .accessibilityHint("When enabled, connects to onion service addresses when available")
            } header: {
                Text("Connection")
            } footer: {
                Text("Route all relay traffic through Tor for enhanced anonymity.")
            }

            Section {
                if bridgeText.isEmpty {
                    Text("No bridges configured")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(bridgeText.split(separator: "\n").map(String.init), id: \.self) { bridge in
                        Text(bridge)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }

                Button("Add Bridge") {
                    showAddBridge = true
                }

                if !bridgeText.isEmpty {
                    Button("Clear All Bridges", role: .destructive) {
                        bridgeText = ""
                        let bridges: [String] = []
                        viewModel.saveTorConfig(enabled: torEnabled, bridges: bridges, preferOnion: preferOnion)
                        successMessage = "Bridges cleared"
                    }
                }
            } header: {
                Text("Bridges")
            } footer: {
                Text("Add obfs4 bridge addresses for censored networks.")
            }

            if !successMessage.isEmpty {
                Section { Text(successMessage).foregroundColor(.green) }
            }
            if !errorMessage.isEmpty {
                Section { Text(errorMessage).foregroundColor(.red) }
            }
        }
        .navigationTitle("Tor Mode")
        .onAppear {
            torEnabled = viewModel.isTorEnabled
            preferOnion = viewModel.torPreferOnion
            bridgeText = viewModel.torBridges.joined(separator: "\n")
        }
        .alert("Add Bridge", isPresented: $showAddBridge) {
            TextField("obfs4 address...", text: $newBridge)
            Button("Add") {
                let trimmed = newBridge.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if bridgeText.isEmpty {
                        bridgeText = trimmed
                    } else {
                        bridgeText += "\n" + trimmed
                    }
                    let bridges = bridgeText.split(separator: "\n").map(String.init)
                    viewModel.saveTorConfig(enabled: torEnabled, bridges: bridges, preferOnion: preferOnion)
                    newBridge = ""
                    successMessage = "Bridge added"
                }
            }
            Button("Cancel", role: .cancel) {
                newBridge = ""
            }
        } message: {
            Text("Enter an obfs4 bridge address")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(VauchiViewModel())
}
