// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ScreenRendererView.swift
// Generic view that renders any ScreenModel from core

import SwiftUI

/// Generic view that renders any core `ScreenModel`.
///
/// Given a screen description from core, this view renders:
/// - Progress indicator (if present)
/// - Title and subtitle
/// - All components via `ComponentView`
/// - Action buttons at the bottom
/// - Toast overlay (auto-dismissing)
///
/// User interactions are forwarded via `onAction`.
struct ScreenRendererView: View {
    let screen: ScreenModel
    let onAction: (UserAction) -> Void

    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Progress bar
                if let progress = screen.progress {
                    ProgressView(
                        value: Double(progress.currentStep),
                        total: Double(progress.totalSteps)
                    )
                    .tint(.cyan)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .accessibilityLabel("Step \(progress.currentStep) of \(progress.totalSteps)")
                    .accessibilityValue(progress.label ?? "\(progress.currentStep) of \(progress.totalSteps)")
                }

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text(screen.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)

                            if let subtitle = screen.subtitle {
                                Text(subtitle)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 24)

                        // Components
                        ForEach(Array(screen.components.enumerated()), id: \.offset) { _, component in
                            ComponentView(component: component, onAction: onAction)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    ForEach(screen.actions) { action in
                        ActionButton(action: action) {
                            onAction(.actionPressed(actionId: action.id))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Toast overlay
            if let message = toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityLabel(message)
                }
                .animation(.easeInOut(duration: 0.3), value: toastMessage)
            }
        }
        .onChange(of: toastComponentMessage) { message in
            if let message {
                showToast(message, durationMs: toastComponentDurationMs)
            }
        }
        .onAppear {
            if let message = toastComponentMessage {
                showToast(message, durationMs: toastComponentDurationMs)
            }
        }
    }

    /// Extract the first ShowToast component's message from the current screen.
    private var toastComponentMessage: String? {
        for component in screen.components {
            if case let .showToast(toast) = component {
                return toast.message
            }
        }
        return nil
    }

    /// Extract the first ShowToast component's duration from the current screen.
    private var toastComponentDurationMs: UInt32 {
        for component in screen.components {
            if case let .showToast(toast) = component {
                return toast.durationMs
            }
        }
        return 3000
    }

    private func showToast(_ message: String, durationMs: UInt32) {
        toastMessage = message
        let duration = max(Double(durationMs) / 1000.0, 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

/// Renders a `ScreenAction` as a styled button.
struct ActionButton: View {
    let action: ScreenAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(action.label)
                .font(isPrimary ? .headline : .subheadline)
                .frame(maxWidth: isPrimary ? .infinity : nil)
                .padding(isPrimary ? 16 : 8)
                .background(background)
                .foregroundColor(foregroundColor)
                .cornerRadius(12)
        }
        .disabled(!action.enabled)
        .opacity(action.enabled ? 1.0 : 0.6)
        .accessibilityLabel(action.label)
    }

    private var isPrimary: Bool {
        action.style == .primary || action.style == .destructive
    }

    private var background: Color {
        switch action.style {
        case .primary: .cyan
        case .secondary: .clear
        case .destructive: .red
        }
    }

    private var foregroundColor: Color {
        switch action.style {
        case .primary: .white
        case .secondary: .cyan
        case .destructive: .white
        }
    }
}
