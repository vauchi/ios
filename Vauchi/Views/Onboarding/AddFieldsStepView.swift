// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AddFieldsStepView.swift
// Quick add phone and email fields
// Based on: features/onboarding.feature @card-creation "Quick add phone and email" scenario

import SwiftUI

struct AddFieldsStepView: View {
    @Binding var phone: String
    @Binding var email: String
    let onContinue: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @FocusState private var focusedField: FocusedField?

    enum FocusedField {
        case phone, email
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
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 32) {
                    // Icon
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)
                        .padding(.top, 24)

                    // Title
                    VStack(spacing: 8) {
                        Text("Add your info")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Help contacts reach you")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    // Quick add fields
                    VStack(spacing: 16) {
                        // Phone
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Phone", systemImage: "phone")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("Your phone number", text: $phone)
                                .textFieldStyle(.plain)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .focused($focusedField, equals: .phone)
                        }

                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Email", systemImage: "envelope")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("Your email address", text: $email)
                                .textFieldStyle(.plain)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .focused($focusedField, equals: .email)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Hint
                    Text("You can add more fields later in your card settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            // Actions
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    AddFieldsStepView(
        phone: .constant(""),
        email: .constant(""),
        onContinue: {},
        onBack: {},
        onSkip: {}
    )
}
