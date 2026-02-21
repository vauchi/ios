// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SecurityStepView.swift
// Simple security explanation
// Based on: features/onboarding.feature @security scenarios

import SwiftUI

struct SecurityStepView: View {
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
                .accessibilityHint("Return to card preview")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            // Content
            VStack(spacing: 32) {
                // Visual diagram
                SecurityDiagram()
                    .accessibilityLabel("Security diagram showing encrypted communication between you and your contacts")

                // Title
                VStack(spacing: 12) {
                    Text("Your info is private")
                        .font(.title)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text("Only you and your contacts can see your information. Not even us.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Key points
                VStack(spacing: 16) {
                    SecurityPoint(
                        icon: "lock.shield",
                        title: "End-to-end encrypted",
                        description: "Your data is encrypted on your device"
                    )

                    SecurityPoint(
                        icon: "person.2",
                        title: "Direct to contacts",
                        description: "Updates go straight to your contacts"
                    )

                    SecurityPoint(
                        icon: "eye.slash",
                        title: "No central database",
                        description: "We can't see your information"
                    )
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Finish setup")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .accessibilityLabel("Finish setup")
                .accessibilityHint("Complete onboarding and start using Vauchi")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

struct SecurityDiagram: View {
    var body: some View {
        HStack(spacing: 20) {
            // Your phone
            VStack(spacing: 4) {
                Image(systemName: "iphone")
                    .font(.system(size: 40))
                    .foregroundColor(.cyan)
                Text("You")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Arrow with lock
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 20))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                }
                .foregroundColor(.green)
                Text("Encrypted")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            // Their phone
            VStack(spacing: 4) {
                Image(systemName: "iphone")
                    .font(.system(size: 40))
                    .foregroundColor(.cyan)
                Text("Contact")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagram showing encrypted communication between your phone and your contact's phone")
    }
}

struct SecurityPoint: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SecurityStepView(onContinue: {}, onBack: {})
}
