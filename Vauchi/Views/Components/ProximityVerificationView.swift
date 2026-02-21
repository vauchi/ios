// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ProximityVerificationView.swift
// Shared proximity verification component for device linking and contact exchange.
// Attempts ultrasonic audio first, falls back to manual confirmation.

import SwiftUI

// MARK: - Verification State

/// Represents the current state of the proximity verification flow.
enum ProximityVerificationState: Equatable {
    case checking
    case ultrasonicInProgress
    case manualRequired
    case verified
    case failed(String)

    static func == (lhs: ProximityVerificationState, rhs: ProximityVerificationState) -> Bool {
        switch (lhs, rhs) {
        case (.checking, .checking),
             (.ultrasonicInProgress, .ultrasonicInProgress),
             (.manualRequired, .manualRequired),
             (.verified, .verified):
            return true
        case let (.failed(lhsMsg), .failed(rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// MARK: - ProximityVerificationView

/// A reusable SwiftUI view for proximity verification.
///
/// Tries ultrasonic audio verification first, then falls back to manual confirmation
/// if ultrasonic is unsupported or fails. Used by both device linking and contact exchange flows.
struct ProximityVerificationView: View {
    @EnvironmentObject var viewModel: VauchiViewModel

    /// The proximity challenge bytes to verify.
    let challenge: Data

    /// Called when proximity verification succeeds (ultrasonic or manual).
    let onVerified: () -> Void

    /// Called when the user cancels the verification flow.
    let onCancel: () -> Void

    @State private var state: ProximityVerificationState = .checking
    @State private var waveformPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            // Header icon
            stateIcon
                .font(.system(size: 56))
                .accessibilityHidden(true)

            // Status text
            stateTitle
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            stateDescription
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Waveform animation during ultrasonic attempt
            if state == .ultrasonicInProgress {
                waveformAnimation
                    .frame(height: 60)
                    .padding(.horizontal, 32)
                    .accessibilityHidden(true)
            }

            Spacer()
                .frame(height: 8)

            // Action buttons
            actionButtons
        }
        .padding(24)
        .onAppear {
            checkCapabilityAndStart()
        }
        .onDisappear {
            viewModel.stopProximityVerification()
        }
    }

    // MARK: - State-Dependent Views

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .checking:
            Image(systemName: "wave.3.right.circle")
                .foregroundColor(.cyan)
        case .ultrasonicInProgress:
            if #available(iOS 17.0, *) {
                Image(systemName: "waveform")
                    .foregroundColor(.cyan)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(.cyan)
            }
        case .manualRequired:
            Image(systemName: "person.2.fill")
                .foregroundColor(.orange)
        case .verified:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var stateTitle: some View {
        switch state {
        case .checking:
            Text("Checking Proximity...")
        case .ultrasonicInProgress:
            Text("Verifying Proximity")
        case .manualRequired:
            Text("Confirm You Are Nearby")
        case .verified:
            Text("Proximity Verified")
        case let .failed(message):
            Text("Verification Failed")
                .accessibilityLabel("Verification failed: \(message)")
        }
    }

    @ViewBuilder
    private var stateDescription: some View {
        switch state {
        case .checking:
            Text("Checking device audio capabilities...")
        case .ultrasonicInProgress:
            Text("Hold both devices close together. Verifying proximity using ultrasonic audio...")
        case .manualRequired:
            Text("Automatic verification is not available. Please confirm that both devices are physically next to each other.")
        case .verified:
            Text("Both devices have been confirmed to be in close proximity.")
        case let .failed(message):
            Text(message)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch state {
            case .checking:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())

                cancelButton

            case .ultrasonicInProgress:
                cancelButton

            case .manualRequired:
                Button(action: {
                    state = .verified
                    onVerified()
                }) {
                    Text("Confirm Nearby")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .accessibilityLabel("Confirm nearby")
                .accessibilityHint("Confirms that both devices are physically next to each other and completes verification")

                cancelButton

            case .verified:
                // No buttons needed; onVerified callback already fired
                EmptyView()

            case .failed:
                Button(action: {
                    state = .checking
                    checkCapabilityAndStart()
                }) {
                    Text("Retry")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .accessibilityLabel("Retry verification")
                .accessibilityHint("Attempts proximity verification again from the beginning")

                cancelButton
            }
        }
        .padding(.horizontal)
    }

    private var cancelButton: some View {
        Button(action: {
            viewModel.stopProximityVerification()
            onCancel()
        }) {
            Text("Cancel")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(10)
        }
        .accessibilityLabel("Cancel verification")
        .accessibilityHint("Stops the proximity verification process and goes back")
    }

    // MARK: - Waveform Animation

    private var waveformAnimation: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0 ..< 20, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.cyan.opacity(0.7))
                        .frame(
                            width: (geometry.size.width - 57) / 20,
                            height: waveformBarHeight(index: index, totalWidth: geometry.size.height)
                        )
                        .animation(
                            Animation.easeInOut(duration: 0.4 + Double(index % 5) * 0.1)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.05),
                            value: waveformPhase
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            waveformPhase = 1
        }
    }

    private func waveformBarHeight(index: Int, totalWidth: CGFloat) -> CGFloat {
        let base: CGFloat = 8
        let maxHeight = totalWidth * 0.9
        let sinValue = sin(CGFloat(index) * 0.5 + waveformPhase * .pi * 2)
        return base + abs(sinValue) * (maxHeight - base)
    }

    // MARK: - Verification Logic

    private func checkCapabilityAndStart() {
        let capability = viewModel.proximityCapability

        switch capability {
        case "full", "emit_only":
            state = .ultrasonicInProgress
            attemptUltrasonicVerification()
        case "receive_only", "none":
            state = .manualRequired
        default:
            state = .manualRequired
        }
    }

    private func attemptUltrasonicVerification() {
        Task {
            // Emit the challenge
            let emitSuccess = viewModel.emitProximityChallenge(challenge)

            if !emitSuccess {
                await MainActor.run {
                    state = .manualRequired
                }
                return
            }

            // Listen for the response
            let response = viewModel.listenForProximityResponse(timeoutMs: 5000)

            await MainActor.run {
                if response != nil {
                    state = .verified
                    onVerified()
                } else {
                    // Ultrasonic timed out or failed — fall back to manual
                    state = .manualRequired
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProximityVerificationView(
        challenge: Data([0x01, 0x02, 0x03, 0x04]),
        onVerified: { print("Verified!") },
        onCancel: { print("Cancelled.") }
    )
    .environmentObject(VauchiViewModel())
}
