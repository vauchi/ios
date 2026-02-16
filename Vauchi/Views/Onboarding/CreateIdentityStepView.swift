// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// CreateIdentityStepView.swift
// Identity creation step - display name input
// Based on: features/onboarding.feature @card-creation scenarios

import SwiftUI

struct CreateIdentityStepView: View {
    @Binding var displayName: String
    let onContinue: () -> Void
    let onBack: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
                .accessibilityHint("Return to welcome screen")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            // Content
            VStack(spacing: 32) {
                // Icon
                Image(systemName: "person.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.cyan)
                    .accessibilityHidden(true)

                // Title
                VStack(spacing: 8) {
                    Text("What's your name?")
                        .font(.title)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text("This is how you'll appear to your contacts")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Name input
                TextField("Your name", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .autocapitalization(.words)
                    .focused($isNameFocused)
                    .submitLabel(.continue)
                    .onSubmit {
                        if isValid {
                            onContinue()
                        }
                    }
                    .padding(.horizontal, 32)
                    .accessibilityLabel("Your name")
                    .accessibilityHint("Enter your display name for your contact card")
            }

            Spacer()

            // Continue button
            VStack(spacing: 8) {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.cyan : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(!isValid)
                .accessibilityLabel("Continue")
                .accessibilityHint("Proceed to add contact fields")

                Text("You can change this later")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFocused = true
            }
        }
    }
}

#Preview {
    CreateIdentityStepView(
        displayName: .constant(""),
        onContinue: {},
        onBack: {}
    )
}
