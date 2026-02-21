// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// PreviewCardStepView.swift
// Preview card before confirming
// Based on: features/onboarding.feature @card-creation "Card preview before finishing" scenario

import SwiftUI

struct PreviewCardStepView: View {
    @ObservedObject var onboardingData: OnboardingData
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.cyan)
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Return to add fields screen")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            // Content
            VStack(spacing: 24) {
                // Title
                VStack(spacing: 8) {
                    Text("Your card")
                        .font(.title)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text("This is how you'll appear to contacts")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Card preview
                VStack(spacing: 0) {
                    // Card header
                    VStack(spacing: 8) {
                        // Avatar placeholder
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(onboardingData.displayName.prefix(1).uppercased())
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .accessibilityHidden(true)

                        Text(onboardingData.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .accessibilityLabel("Display name: \(onboardingData.displayName)")
                    }
                    .padding(.vertical, 24)

                    Divider()

                    // Fields
                    VStack(spacing: 0) {
                        if !onboardingData.phone.isEmpty {
                            PreviewFieldRow(icon: "phone", label: "Phone", value: onboardingData.phone)
                        }

                        if !onboardingData.email.isEmpty {
                            PreviewFieldRow(icon: "envelope", label: "Email", value: onboardingData.email)
                        }

                        if onboardingData.phone.isEmpty, onboardingData.email.isEmpty {
                            Text("No additional info yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 24)
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Looks good!")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Looks good!")
                .accessibilityHint("Confirm card and proceed to security information")

                Button(action: onBack) {
                    Text("Edit card")
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                }
                .accessibilityLabel("Edit card")
                .accessibilityHint("Go back to edit your contact information")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct PreviewFieldRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview {
    let data = OnboardingData()
    data.displayName = "Alice Smith"
    data.phone = "+1 555-123-4567"
    data.email = "alice@example.com"

    return PreviewCardStepView(
        onboardingData: data,
        onContinue: {},
        onBack: {}
    )
}
