// SetupView.swift
// Identity creation view

import SwiftUI

struct SetupView: View {
    @EnvironmentObject var viewModel: VauchiViewModel
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 60))
                    .foregroundColor(.cyan)

                Text("Welcome to Vauchi")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Privacy-focused contact card exchange")
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Display Name")
                    .font(.headline)

                TextField("Enter your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)
                    .disabled(isLoading)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(action: createIdentity) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isLoading ? "Creating..." : "Get Started")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(name.isEmpty ? Color.gray : Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(name.isEmpty || isLoading)
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
