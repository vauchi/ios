// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// RecoveryView.swift
// Recovery claim and vouching UI for Vauchi iOS

import SwiftUI

struct RecoveryView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var selectedTab = 0
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Mode", selection: $selectedTab) {
                    Text("Recover").tag(0)
                    Text("Help Others").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityLabel("Recovery mode")
                .accessibilityHint("Switch between recovering your own identity or helping others recover theirs")

                // Content
                TabView(selection: $selectedTab) {
                    RecoverIdentityTab()
                        .tag(0)
                    HelpOthersTab()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(localizationService.t("recovery.title"))
        }
    }
}

// MARK: - Recover Identity Tab

struct RecoverIdentityTab: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @State private var showClaimSheet = false
    @State private var showAddVoucherSheet = false
    @State private var showStatusSheet = false
    @State private var trustedCount: UInt32 = 0
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(tokens.spacing.lg)) {
                // Info card
                VStack(spacing: CGFloat(tokens.spacing.smMd)) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundColor(.cyan)
                        .accessibilityHidden(true)

                    Text("Lost Your Device?")
                        .font(Font.title2.weight(.semibold))

                    Text("You can recover your contact relationships through social vouching.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

                // Recovery settings
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizationService.t("recovery.status"))
                        .font(.headline)

                    HStack {
                        Text("Required vouchers:")
                        Spacer()
                        Text("3")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Claim expiry:")
                        Spacer()
                        Text("7 days")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Trusted contacts:")
                        Spacer()
                        Text("\(trustedCount)/3")
                            .foregroundColor(trustedCount >= 3 ? .secondary : .red)
                    }
                    if trustedCount < 3 {
                        Text("Mark \(3 - trustedCount) more contact(s) as trusted for recovery")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                .task {
                    do {
                        trustedCount = try await viewModel.trustedContactCount()
                    } catch {
                        // Graceful failure
                    }
                }

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    Text(localizationService.t("recovery.how_it_works"))
                        .font(.headline)

                    RecoveryStepRow(number: 1, title: "Create New Identity", description: "First, create a new identity on your new device.")
                    RecoveryStepRow(number: 2, title: "Generate Recovery Claim", description: "Create a claim using your OLD public key from your lost identity.")
                    RecoveryStepRow(number: 3, title: "Collect Vouchers", description: "Meet with 3+ trusted contacts in person. Have them vouch for your recovery.")
                    RecoveryStepRow(number: 4, title: "Share Recovery Proof", description: "Once you have enough vouchers, share your recovery proof with all contacts.")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

                // Action buttons
                VStack(spacing: CGFloat(tokens.spacing.smMd)) {
                    Button(action: { showClaimSheet = true }) {
                        Text("Start Recovery Process")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.white)
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .accessibilityLabel("Start recovery process")
                    .accessibilityHint("Begin recovering your identity using social vouching")

                    Button(action: { showAddVoucherSheet = true }) {
                        Text("Add Received Voucher")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .accessibilityLabel("Add received voucher")
                    .accessibilityHint("Submit a voucher received from a trusted contact")

                    Button(action: { showStatusSheet = true }) {
                        Text("Check Recovery Status")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                    }
                    .accessibilityLabel("Check recovery status")
                    .accessibilityHint("View progress of your current recovery attempt")
                }
            }
            .padding()
        }
        .sheet(isPresented: $showClaimSheet) {
            CreateClaimSheet()
        }
        .sheet(isPresented: $showAddVoucherSheet) {
            AddVoucherSheet()
        }
        .sheet(isPresented: $showStatusSheet) {
            RecoveryStatusSheet()
        }
    }
}

// MARK: - Help Others Tab

struct HelpOthersTab: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @State private var showVouchSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(tokens.spacing.lg)) {
                // Info card
                VStack(spacing: CGFloat(tokens.spacing.smMd)) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                        .accessibilityHidden(true)

                    Text("Help a Contact Recover")
                        .font(Font.title2.weight(.semibold))

                    Text("If a contact lost their device, you can vouch for their identity.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

                // Warning
                HStack(spacing: CGFloat(tokens.spacing.smMd)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    Text("Only vouch for someone you can verify IN PERSON. This prevents identity theft.")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                .accessibilityElement(children: .combine)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    Text("How to Vouch")
                        .font(.headline)

                    RecoveryStepRow(number: 1, title: "Verify Identity", description: "Meet your contact in person. Verify they are who they claim to be.")
                    RecoveryStepRow(number: 2, title: "Get Their Claim", description: "They will share their claim data with you.")
                    RecoveryStepRow(number: 3, title: "Create Voucher", description: "Sign a voucher confirming their identity.")
                    RecoveryStepRow(number: 4, title: "Share Voucher", description: "Give them the voucher data to add to their recovery proof.")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

                // Action button
                Button(action: { showVouchSheet = true }) {
                    Text("Vouch for Someone")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                }
                .accessibilityLabel("Vouch for someone")
                .accessibilityHint("Help a contact recover their identity by vouching for them")
            }
            .padding()
        }
        .sheet(isPresented: $showVouchSheet) {
            CreateVoucherSheet()
        }
    }
}

// MARK: - Create Claim Sheet

struct CreateClaimSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.dismiss) var dismiss
    @State private var oldPublicKey = ""
    @State private var isCreating = false
    @State private var generatedClaim: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let claim = generatedClaim {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                            .accessibilityHidden(true)

                        Text("Claim Created!")
                            .font(Font.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)

                        Text("Share this claim with your trusted contacts:")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text(String(claim.prefix(60)) + "...")
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Button(action: {
                            UIPasteboard.general.string = claim
                        }) {
                            Label("Copy Claim Data", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.cyan)
                                .foregroundColor(.white)
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                        }
                        .accessibilityLabel("Copy claim data")
                        .accessibilityHint("Copies claim data to clipboard to share with trusted contacts")
                    }
                    .padding()
                } else {
                    // Input state
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Enter your OLD public key from your backup or previous device:")
                            .foregroundColor(.secondary)

                        TextField("Old Public Key (hex)", text: $oldPublicKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .disabled(isCreating)
                            .accessibilityLabel("Old public key")
                            .accessibilityHint("Enter your old public key from your backup or previous device")

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: createClaim) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Create Claim")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(oldPublicKey.count >= 64 && !isCreating ? Color.cyan : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                        }
                        .disabled(oldPublicKey.count < 64 || isCreating)
                        .accessibilityLabel("Create claim")
                        .accessibilityHint("Generate a recovery claim using the old public key")
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle(generatedClaim != nil ? "Claim Created" : "Create Recovery Claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(generatedClaim != nil ? "Done" : "Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func createClaim() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let claim = try await viewModel.createRecoveryClaim(oldPkHex: oldPublicKey.trimmingCharacters(in: .whitespacesAndNewlines))
                generatedClaim = claim.claimData
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Create Voucher Sheet

struct CreateVoucherSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.dismiss) var dismiss
    @State private var claimData = ""
    @State private var isParsing = false
    @State private var isCreatingVoucher = false
    @State private var parsedClaim: VauchiRepository.RecoveryClaimInfo?
    @State private var generatedVoucher: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let voucher = generatedVoucher {
                    // Voucher created
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                            .accessibilityHidden(true)

                        Text("Voucher Created!")
                            .font(Font.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)

                        Text("Give this voucher to your contact:")
                            .foregroundColor(.secondary)

                        Text(String(voucher.prefix(60)) + "...")
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Button(action: {
                            UIPasteboard.general.string = voucher
                        }) {
                            Label("Copy Voucher Data", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                        }
                        .accessibilityLabel("Copy voucher data")
                        .accessibilityHint("Copies voucher data to clipboard to share with the recovering contact")
                    }
                    .padding()
                } else if let claim = parsedClaim {
                    // Claim verified, confirm vouching
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Claim Details")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Old ID:")
                                Spacer()
                                Text(String(claim.oldPublicKey.prefix(16)) + "...")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            HStack {
                                Text("New ID:")
                                Spacer()
                                Text(String(claim.newPublicKey.prefix(16)) + "...")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                        if claim.isExpired {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("This claim has EXPIRED!")
                                    .foregroundColor(.red)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Verify this person's identity IN PERSON before vouching!")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)

                            Button(action: createVoucher) {
                                HStack {
                                    if isCreatingVoucher {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Create Voucher")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(!isCreatingVoucher ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                            }
                            .disabled(isCreatingVoucher)
                            .accessibilityLabel("Create voucher")
                            .accessibilityHint("Generate a voucher to help this contact recover their identity")
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                } else {
                    // Input claim data
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Paste the recovery claim data from your contact:")
                            .foregroundColor(.secondary)

                        TextField("Claim Data (base64)", text: $claimData)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .disabled(isParsing)

                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Verify this person's identity IN PERSON before vouching!")
                                .font(.caption)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: parseClaim) {
                            HStack {
                                if isParsing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Verify Claim")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(claimData.count >= 20 && !isParsing ? Color.cyan : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                        }
                        .disabled(claimData.count < 20 || isParsing)
                        .accessibilityLabel("Verify claim")
                        .accessibilityHint("Parse and verify the recovery claim data")
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle(
                generatedVoucher != nil ? "Voucher Created" :
                    parsedClaim != nil ? "Confirm Voucher" : "Vouch for Recovery"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(generatedVoucher != nil ? "Done" : parsedClaim != nil ? "Back" : "Cancel") {
                        if parsedClaim != nil, generatedVoucher == nil {
                            parsedClaim = nil
                            errorMessage = nil
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func parseClaim() {
        isParsing = true
        errorMessage = nil

        Task {
            do {
                parsedClaim = try await viewModel.parseRecoveryClaim(claimB64: claimData.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                errorMessage = "Invalid claim data: \(error.localizedDescription)"
            }
            isParsing = false
        }
    }

    private func createVoucher() {
        isCreatingVoucher = true
        errorMessage = nil

        Task {
            do {
                let voucher = try await viewModel.createRecoveryVoucher(claimB64: claimData.trimmingCharacters(in: .whitespacesAndNewlines))
                generatedVoucher = voucher.voucherData
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreatingVoucher = false
        }
    }
}

// MARK: - Add Voucher Sheet

struct AddVoucherSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.dismiss) var dismiss
    @State private var voucherData = ""
    @State private var isAdding = false
    @State private var progress: VauchiRepository.RecoveryProgressInfo?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let progress {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: progress.isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(progress.isComplete ? .green : .blue)
                            .accessibilityHidden(true)

                        Text(progress.isComplete ? "Recovery Complete!" : "Voucher Added!")
                            .font(Font.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Vouchers collected:")
                                Spacer()
                                Text("\(progress.vouchersCollected) / \(progress.vouchersNeeded)")
                                    .font(Font.body.weight(.semibold))
                            }

                            ProgressView(value: Double(progress.vouchersCollected), total: Double(progress.vouchersNeeded))
                                .tint(progress.isComplete ? .green : .cyan)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                        if progress.isComplete {
                            Text("Your identity has been recovered! Your contacts will now trust your new identity.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button(action: {
                                Task {
                                    if let proof = try? await viewModel.getRecoveryProof() {
                                        UIPasteboard.general.string = proof
                                    }
                                }
                            }) {
                                Label("Copy Recovery Proof", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                            }
                        } else {
                            Text("Collect \(progress.vouchersNeeded - progress.vouchersCollected) more voucher(s) from trusted contacts.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                } else {
                    // Input state
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Paste the voucher data you received from a trusted contact:")
                            .foregroundColor(.secondary)

                        TextField("Voucher Data (base64)", text: $voucherData)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .disabled(isAdding)

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: addVoucher) {
                            HStack {
                                if isAdding {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Add Voucher")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(voucherData.count >= 20 && !isAdding ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                        }
                        .disabled(voucherData.count < 20 || isAdding)
                        .accessibilityLabel("Add voucher")
                        .accessibilityHint("Submit the voucher to your recovery claim")
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle(progress != nil ? "Voucher Added" : "Add Voucher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(progress != nil ? "Done" : "Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addVoucher() {
        isAdding = true
        errorMessage = nil

        Task {
            do {
                progress = try await viewModel.addRecoveryVoucher(voucherB64: voucherData.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}

// MARK: - Recovery Status Sheet

struct RecoveryStatusSheet: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var status: VauchiRepository.RecoveryProgressInfo?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading status...")
                } else if let status {
                    VStack(spacing: 16) {
                        Image(systemName: status.isComplete ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.system(size: 60))
                            .foregroundColor(status.isComplete ? .green : .cyan)
                            .accessibilityHidden(true)

                        Text(status.isComplete ? "Recovery Complete" : "Recovery In Progress")
                            .font(Font.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Old Identity:")
                                Spacer()
                                Text(String(status.oldPublicKey.prefix(12)) + "...")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            HStack {
                                Text("New Identity:")
                                Spacer()
                                Text(String(status.newPublicKey.prefix(12)) + "...")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            Divider()
                            HStack {
                                Text("Vouchers:")
                                Spacer()
                                Text("\(status.vouchersCollected) / \(status.vouchersNeeded)")
                                    .font(Font.body.weight(.semibold))
                                    .foregroundColor(status.isComplete ? .green : .primary)
                            }

                            ProgressView(value: Double(status.vouchersCollected), total: Double(status.vouchersNeeded))
                                .tint(status.isComplete ? .green : .cyan)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

                        if status.isComplete {
                            Button(action: copyProof) {
                                Label("Copy Recovery Proof", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                            }

                            Text("Share this proof with your contacts to restore your relationships.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("You need \(status.vouchersNeeded - status.vouchersCollected) more voucher(s). Meet with trusted contacts in person to collect them.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)

                        Text("No Active Recovery")
                            .font(Font.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)

                        Text("You don't have an active recovery claim. Start a new recovery process if you need to recover a lost identity.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle("Recovery Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadStatus()
            }
        }
    }

    private func loadStatus() {
        Task {
            do {
                status = try await viewModel.getRecoveryStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func copyProof() {
        Task {
            if let proof = try? await viewModel.getRecoveryProof() {
                UIPasteboard.general.string = proof
            }
        }
    }
}

// MARK: - Recovery Step Row

struct RecoveryStepRow: View {
    @Environment(\.designTokens) private var tokens
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(tokens.spacing.smMd)) {
            Text("\(number)")
                .font(Font.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Color.cyan.opacity(0.2))
                .foregroundColor(.cyan)
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Font.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(description)")
    }
}

#Preview {
    RecoveryView()
        .environmentObject(VauchiViewModel())
}
