// RecoveryView.swift
// Recovery claim and vouching UI for Vauchi iOS

import SwiftUI

struct RecoveryView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var selectedTab = 0

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

                // Content
                TabView(selection: $selectedTab) {
                    RecoverIdentityTab()
                        .tag(0)
                    HelpOthersTab()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Recovery")
        }
    }
}

// MARK: - Recover Identity Tab

struct RecoverIdentityTab: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var showClaimSheet = false
    @State private var showAddVoucherSheet = false
    @State private var showStatusSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Info card
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundColor(.cyan)

                    Text("Lost Your Device?")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("You can recover your contact relationships through social vouching.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Recovery settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Settings")
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
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    Text("How Recovery Works")
                        .font(.headline)

                    RecoveryStepRow(number: 1, title: "Create New Identity", description: "First, create a new identity on your new device.")
                    RecoveryStepRow(number: 2, title: "Generate Recovery Claim", description: "Create a claim using your OLD public key from your lost identity.")
                    RecoveryStepRow(number: 3, title: "Collect Vouchers", description: "Meet with 3+ trusted contacts in person. Have them vouch for your recovery.")
                    RecoveryStepRow(number: 4, title: "Share Recovery Proof", description: "Once you have enough vouchers, share your recovery proof with all contacts.")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: { showClaimSheet = true }) {
                        Text("Start Recovery Process")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: { showAddVoucherSheet = true }) {
                        Text("Add Received Voucher")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: { showStatusSheet = true }) {
                        Text("Check Recovery Status")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
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
    @State private var showVouchSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Info card
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("Help a Contact Recover")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("If a contact lost their device, you can vouch for their identity.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Warning
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Only vouch for someone you can verify IN PERSON. This prevents identity theft.")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)

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
                .cornerRadius(12)

                // Action button
                Button(action: { showVouchSheet = true }) {
                    Text("Vouch for Someone")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
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

                        Text("Claim Created!")
                            .font(.title2)
                            .fontWeight(.semibold)

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
                                .cornerRadius(10)
                        }
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
                            .cornerRadius(10)
                        }
                        .disabled(oldPublicKey.count < 64 || isCreating)
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

                        Text("Voucher Created!")
                            .font(.title2)
                            .fontWeight(.semibold)

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
                                .cornerRadius(10)
                        }
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
                                .cornerRadius(10)
                            }
                            .disabled(isCreatingVoucher)
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
                            .cornerRadius(10)
                        }
                        .disabled(claimData.count < 20 || isParsing)
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
                        if parsedClaim != nil && generatedVoucher == nil {
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
    @Environment(\.dismiss) var dismiss
    @State private var voucherData = ""
    @State private var isAdding = false
    @State private var progress: VauchiRepository.RecoveryProgressInfo?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let progress = progress {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: progress.isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(progress.isComplete ? .green : .blue)

                        Text(progress.isComplete ? "Recovery Complete!" : "Voucher Added!")
                            .font(.title2)
                            .fontWeight(.semibold)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Vouchers collected:")
                                Spacer()
                                Text("\(progress.vouchersCollected) / \(progress.vouchersNeeded)")
                                    .fontWeight(.semibold)
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
                                    .cornerRadius(10)
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
                            .cornerRadius(10)
                        }
                        .disabled(voucherData.count < 20 || isAdding)
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
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var status: VauchiRepository.RecoveryProgressInfo?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading status...")
                } else if let status = status {
                    VStack(spacing: 16) {
                        Image(systemName: status.isComplete ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.system(size: 60))
                            .foregroundColor(status.isComplete ? .green : .cyan)

                        Text(status.isComplete ? "Recovery Complete" : "Recovery In Progress")
                            .font(.title2)
                            .fontWeight(.semibold)

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
                                    .fontWeight(.semibold)
                                    .foregroundColor(status.isComplete ? .green : .primary)
                            }

                            ProgressView(value: Double(status.vouchersCollected), total: Double(status.vouchersNeeded))
                                .tint(status.isComplete ? .green : .cyan)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        if status.isComplete {
                            Button(action: copyProof) {
                                Label("Copy Recovery Proof", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
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

                        Text("No Active Recovery")
                            .font(.title2)
                            .fontWeight(.semibold)

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
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Color.cyan.opacity(0.2))
                .foregroundColor(.cyan)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    RecoveryView()
        .environmentObject(VauchiViewModel())
}
