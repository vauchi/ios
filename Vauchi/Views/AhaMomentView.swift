// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AhaMomentView.swift
// Progressive onboarding hint display

import SwiftUI
import VauchiMobile

/// Displays an "Aha moment" - a progressive onboarding hint at key milestones
struct AhaMomentView: View {
    let moment: MobileAhaMoment
    let onDismiss: () -> Void

    @State private var showAnimation = true

    var body: some View {
        VStack(spacing: 24) {
            // Celebration animation if enabled
            if moment.hasAnimation && showAnimation {
                LottieAnimationPlaceholder()
                    .frame(width: 120, height: 120)
            } else {
                // Icon based on moment type
                momentIcon
                    .font(.system(size: 48))
                    .foregroundColor(.cyan)
            }

            // Title
            Text(moment.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Message
            Text(moment.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Dismiss button
            Button(action: onDismiss) {
                Text("Got it!")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(radius: 20)
        )
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    var momentIcon: some View {
        switch moment.momentType {
        case .cardCreationComplete:
            Image(systemName: "checkmark.circle.fill")
        case .firstEdit:
            Image(systemName: "pencil.circle.fill")
        case .firstContactAdded:
            Image(systemName: "person.badge.plus")
        case .firstUpdateReceived:
            Image(systemName: "arrow.down.circle.fill")
        case .firstOutboundDelivered:
            Image(systemName: "arrow.up.circle.fill")
        }
    }
}

/// Placeholder for Lottie animation (replace with actual implementation)
struct LottieAnimationPlaceholder: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 64))
            .foregroundColor(.cyan)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}

/// Overlay modifier for displaying aha moments
struct AhaMomentOverlay: ViewModifier {
    @Binding var moment: MobileAhaMoment?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let moment = moment {
                    ZStack {
                        // Dimmed background
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                self.moment = nil
                            }

                        // Aha moment card
                        AhaMomentView(moment: moment) {
                            self.moment = nil
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: moment)
                }
            }
    }
}

extension View {
    /// Displays an aha moment overlay when the binding is non-nil
    func ahaMomentOverlay(_ moment: Binding<MobileAhaMoment?>) -> some View {
        modifier(AhaMomentOverlay(moment: moment))
    }
}

#Preview {
    VStack {
        Text("Background Content")
    }
    .ahaMomentOverlay(.constant(MobileAhaMoment(
        momentType: .cardCreationComplete,
        title: "Your Card is Ready!",
        message: "You've created your first Vauchi card. Share it with friends to stay connected.",
        hasAnimation: true
    )))
}
