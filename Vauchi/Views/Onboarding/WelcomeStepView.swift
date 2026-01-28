// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// WelcomeStepView.swift
// First step of onboarding - value proposition
// Based on: features/onboarding.feature @first-launch scenarios

import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero section
            VStack(spacing: 24) {
                // App icon/logo
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Title
                Text("Vauchi")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Tagline
                Text("Contact cards that stay up to date")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Value proposition cards
            VStack(spacing: 16) {
                ValuePropRow(
                    icon: "qrcode.viewfinder",
                    title: "Exchange in person",
                    description: "Scan QR codes to connect"
                )

                ValuePropRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Auto-updating",
                    description: "Your info stays current"
                )

                ValuePropRow(
                    icon: "lock.shield",
                    title: "Private & secure",
                    description: "End-to-end encrypted"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: onRestore) {
                    Text("I have a backup")
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

struct ValuePropRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.cyan)
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
        .padding(.vertical, 8)
    }
}

#Preview {
    WelcomeStepView(onContinue: {}, onRestore: {})
}
