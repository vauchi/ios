// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Unified passcode entry shown after biometric auth. Accepts either
/// the app password or the duress PIN (4–64 chars, any character set);
/// `core.authenticate()` decides Normal vs Duress mode based on which
/// secret matched.
///
/// Visually identical regardless of which secret is entered — the
/// observer cannot distinguish normal from duress authentication.
///
/// Note on zeroization: Swift String is immutable/COW — we can't
/// guarantee heap scrubbing. We clear the @State variable immediately
/// after use and on background transitions. The Rust core zeroizes
/// the password after hashing (ZeroizeOnDrop).
struct AppPasswordView: View {
    @ObservedObject var viewModel: VauchiViewModel
    @ObservedObject private var localizationService = LocalizationService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var pin = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)

            Text(localizationService.t("app_password.title"))
                .font(Font.title2.weight(.semibold))

            Text(localizationService.t("app_password.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            SecureField(localizationService.t("app_password.password_placeholder"), text: $pin)
                .textContentType(.password)
                .focused($pinFocused)
                .multilineTextAlignment(.center)
                .font(.title3.monospaced())
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 48)
                .onChange(of: pin) { newValue in
                    let clamped = PasscodePolicy.clamp(newValue)
                    if clamped != newValue {
                        pin = clamped
                    }
                    errorMessage = nil
                }
                .disabled(isAuthenticating)
                .accessibilityLabel("App password input")

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                authenticate()
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else {
                    Text(localizationService.t("app_password.unlock_button"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!PasscodePolicy.isValid(pin) || isAuthenticating)
            .padding(.horizontal, 48)
            .accessibilityLabel("Unlock with app password")

            Button {
                pin = ""
                viewModel.appState = .authenticationRequired
            } label: {
                Text(localizationService.t("app_password.cancel_button"))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .onAppear { pinFocused = true }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                pin = ""
                errorMessage = nil
            }
        }
    }

    private func authenticate() {
        let entered = pin
        pin = ""
        isAuthenticating = true
        Task {
            do {
                try await viewModel.authenticateAppPassword(entered)
            } catch {
                errorMessage = localizationService.t("app_password.error_incorrect")
                isAuthenticating = false
                pinFocused = true
            }
        }
    }
}
