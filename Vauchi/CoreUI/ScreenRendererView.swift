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
    @State private var toastUndoActionId: String?

    var body: some View {
        ZStack(alignment: .top) {
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
                ToastOverlayView(
                    message: message,
                    undoActionId: toastUndoActionId,
                    onAction: onAction,
                    onDismiss: {
                        withAnimation {
                            toastMessage = nil
                            toastUndoActionId = nil
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .padding(.horizontal, 24)
                .zIndex(100)
            }
        }
        .onChange(of: screen.screenId) { _ in
            checkForToastComponent()
        }
        .onChange(of: screen.components.count) { _ in
            checkForToastComponent()
        }
        .onAppear {
            checkForToastComponent()
        }
    }

    private func checkForToastComponent() {
        for component in screen.components {
            if case let .showToast(toast) = component {
                let message = toast.message
                withAnimation {
                    toastMessage = message
                    toastUndoActionId = toast.undoActionId
                }
                let dismissDelay = Double(toast.durationMs) / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
                    // Only dismiss if this is still the same toast
                    if toastMessage == message {
                        withAnimation {
                            toastMessage = nil
                            toastUndoActionId = nil
                        }
                    }
                }
                break
            }
        }
    }
}

/// Toast overlay view shown at the top of the screen.
struct ToastOverlayView: View {
    let message: String
    let undoActionId: String?
    let onAction: (UserAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)

            if let undoId = undoActionId {
                Button("Undo") {
                    onAction(.undoPressed(actionId: undoId))
                    onDismiss()
                }
                .font(.subheadline.bold())
                .foregroundColor(.cyan)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Toast: \(message)")
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
