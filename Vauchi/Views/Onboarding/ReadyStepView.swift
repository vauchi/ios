// ReadyStepView.swift
// Completion screen with first exchange prompt
// Based on: features/onboarding.feature @completion and @first-exchange scenarios

import SwiftUI

struct ReadyStepView: View {
    @State private var showConfetti = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Celebration
            VStack(spacing: 24) {
                // Success icon with animation
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                        .scaleEffect(showConfetti ? 1.0 : 0.5)
                        .opacity(showConfetti ? 1.0 : 0.0)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showConfetti)

                // Title
                VStack(spacing: 8) {
                    Text("You're all set!")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Your card is ready to share")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Next steps
            VStack(spacing: 16) {
                Text("What's next?")
                    .font(.headline)
                    .foregroundColor(.secondary)

                NextStepCard(
                    icon: "qrcode.viewfinder",
                    title: "Exchange with someone",
                    description: "Find a friend nearby and scan each other's QR codes"
                )

                NextStepCard(
                    icon: "rectangle.stack.badge.plus",
                    title: "Add more info",
                    description: "Customize your card with more contact details"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // The main app will take over automatically
            // This is just a brief celebration screen
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showConfetti = true
            }
        }
    }
}

struct NextStepCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.cyan)
                .frame(width: 44, height: 44)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    ReadyStepView()
}
