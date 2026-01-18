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

                // Action button
                Button(action: { showClaimSheet = true }) {
                    Text("Start Recovery Process")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showClaimSheet) {
            CreateClaimSheet()
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
                            .font(.caption)
                            .fontDesign(.monospaced)
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

                        TextField("Old Public Key (hex)", text: $oldPublicKey, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .fontDesign(.monospaced)
                            .lineLimit(2...4)
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
                            .font(.caption)
                            .fontDesign(.monospaced)
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
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }
                            HStack {
                                Text("New ID:")
                                Spacer()
                                Text(String(claim.newPublicKey.prefix(16)) + "...")
                                    .font(.caption)
                                    .fontDesign(.monospaced)
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

                        TextField("Claim Data (base64)", text: $claimData, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .fontDesign(.monospaced)
                            .lineLimit(3...6)
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
