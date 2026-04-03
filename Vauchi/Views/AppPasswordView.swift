// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// App password screen shown after biometric auth when duress mode
/// is configured. Collects a 6-digit PIN and routes it through
/// core.authenticate() which determines Normal vs Duress mode.
///
/// Visually identical regardless of which PIN is entered — the
/// observer cannot distinguish normal from duress authentication.
struct AppPasswordView: View {
    @ObservedObject var viewModel: VauchiViewModel

    @State private var pin = ""
    @State private var errorMessage: String?
    @FocusState private var pinFocused: Bool

    private let pinLength = 6

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)

            Text("Enter Password")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your app password to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Password", text: $pin)
                .keyboardType(.numberPad)
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
                    // Limit to digits and max length
                    let filtered = String(
                        newValue.filter(\.isNumber)
                            .prefix(pinLength)
                    )
                    if filtered != newValue {
                        pin = filtered
                    }
                    errorMessage = nil
                }
                .accessibilityLabel("App password input")

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                authenticate()
            } label: {
                Text("Unlock")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pin.count != pinLength)
            .padding(.horizontal, 48)
            .accessibilityLabel("Unlock with app password")

            Spacer()
            Spacer()
        }
        .padding()
        .onAppear { pinFocused = true }
    }

    private func authenticate() {
        do {
            try viewModel.authenticateAppPassword(pin)
        } catch {
            errorMessage = "Incorrect password"
            pin = ""
        }
    }
}
