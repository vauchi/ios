// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SetupView.swift
// Identity creation view

import CoreUIModels
import SwiftUI

struct SetupView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @Environment(\.designTokens) private var tokens
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @ObservedObject private var localizationService = LocalizationService.shared

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 60))
                    .foregroundColor(.cyan)
                    .accessibilityHidden(true)

                Text(localizationService.t("welcome.title"))
                    .font(Font.title.weight(.bold))
                    .accessibilityIdentifier("setup.welcome.title")
                    .accessibilityAddTraits(.isHeader)

                Text(localizationService.t("app.tagline"))
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("setup.welcome.description")
            }
            .accessibilityElement(children: .combine)

            Spacer()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                Text(localizationService.t("settings.display_name"))
                    .font(.headline)
                    .accessibilityHidden(true) // Label is associated with text field

                TextField("Enter your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)
                    .disabled(isLoading)
                    .accessibilityIdentifier("setup.name.field")
                    .accessibilityLabel("Display name")
                    .accessibilityHint("Enter the name others will see when you exchange cards")

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .accessibilityIdentifier("error.message")
                        .accessibilityLabel("Error: \(error)")
                }

                Button(action: createIdentity) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .accessibilityIdentifier("loading.indicator")
                        }
                        Text(isLoading ? "Creating..." : localizationService.t("setup.create"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(name.isEmpty ? Color.gray : Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
                }
                .disabled(name.isEmpty || isLoading)
                .accessibilityIdentifier("setup.create.button")
                .accessibilityLabel(isLoading ? "Creating identity" : "Get Started")
                .accessibilityHint(name.isEmpty ? "Enter your name first" : "Creates your identity and contact card")
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func createIdentity() {
        guard !name.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await viewModel.createIdentity(name: name)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(VauchiViewModel())
}
