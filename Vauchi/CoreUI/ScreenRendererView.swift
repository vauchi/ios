// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Generic view that renders any ScreenModel from core

import CoreUIModels
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

    private var spacing: SpacingTokens {
        screen.tokens.spacing
    }

    private var radius: BorderRadiusTokens {
        screen.tokens.borderRadius
    }

    /// Raw-value compare so this compiles against vauchi-platform-swift
    /// releases that predate `ScreenLayout.pinned`; the decoder rejects
    /// "Pinned" on those versions anyway, so the branch is inert until
    /// the package pin bumps. Switch to `== .pinned` at that bump.
    private var isPinned: Bool {
        screen.layout.rawValue == "Pinned"
    }

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
                    .padding(.top, CGFloat(spacing.sm))
                    .accessibilityLabel("Step \(progress.currentStep) of \(progress.totalSteps)")
                    .accessibilityValue(progress.label ?? "\(progress.currentStep) of \(progress.totalSteps)")
                }

                // Content region. `.fixed` (the multi_stage_exchange QR +
                // camera) must NOT scroll — it fills the viewport so the live
                // QR/camera size to the available space and never reflow. The
                // content stack distributes that height itself: the display QR
                // grows to claim the room while the scan camera stays a small
                // fixed square. `.scroll` and Pinned keep the scrolling
                // region; under Pinned the list's rows compose lazily
                // (LazyVStack) inside this ScrollView — pinning the chrome
                // instead starved the list under tall action footers,
                // device-verified on Android
                // (2026-06-11-contacts-list-windowing-design). The Spacer
                // pushes the action buttons to the bottom.
                if screen.layout == .fixed {
                    scrollableContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        scrollableContent
                            .environment(\.listScrollHost, isPinned)
                    }
                    Spacer()
                }

                // Action buttons
                VStack(spacing: CGFloat(radius.mdLg)) {
                    ForEach(screen.actions) { action in
                        ActionButton(action: action) {
                            onAction(.actionPressed(actionId: action.id))
                        }
                    }
                }
                .padding(.horizontal, CGFloat(spacing.lg))
                .padding(.bottom, CGFloat(spacing.lg))
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
                .padding(.top, CGFloat(spacing.sm))
                .padding(.horizontal, CGFloat(spacing.lg))
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
        .environment(\.designTokens, screen.tokens)
    }

    /// Header + components stack.
    private var scrollableContent: some View {
        // Fixed (exchange) screens pack tightly and hug the horizontal edges
        // so the display QR grows large; scrolling screens keep the roomier
        // `lg` rhythm and gutter.
        let isFixed = screen.layout == .fixed
        return VStack(spacing: CGFloat(isFixed ? spacing.sm : spacing.lg)) {
            // Header
            VStack(spacing: CGFloat(spacing.sm)) {
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
            .padding(.top, CGFloat(isFixed ? spacing.sm : spacing.lg))

            // Components
            ForEach(Array(screen.components.enumerated()), id: \.offset) { _, component in
                ComponentView(component: component, onAction: onAction)
            }
        }
        .padding(.horizontal, CGFloat(isFixed ? spacing.sm : spacing.lg))
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
    @Environment(\.designTokens) private var tokens

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
            RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.mdLg))
                .fill(Color.black.opacity(0.85))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Toast: \(message)")
    }
}

/// Renders a `ScreenAction` as a styled button.
///
/// Secondary actions render as outlined full-width pills, matching
/// Android's `OutlinedButton` treatment in
/// `android/app/src/main/kotlin/app/vauchi/ui/coreui/ScreenRenderer.kt`.
/// Both frontends consume the same `ScreenAction` set from core (e.g.
/// `add_field` / `toggle_view` / `preview-as-picker` on My Card) — the
/// renderer must give them equivalent visual weight on every platform.
/// The prior iOS rendering used bare cyan text labels (no outline, no
/// frame), which the 2026-05-21 walkthrough flagged as humble-UI
/// parity violation item 3 in
/// `_private/docs/problems/2026-05-21-ios-shell-issues-from-walkthrough`.
struct ActionButton: View {
    let action: ScreenAction
    let onTap: () -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        Button(action: onTap) {
            Text(action.label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(background)
                .foregroundColor(foregroundColor)
                .overlay(outline)
                .cornerRadius(CGFloat(tokens.borderRadius.mdLg))
        }
        .disabled(!action.enabled)
        .opacity(action.enabled ? 1.0 : 0.6)
        .accessibilityIdentifier(action.id)
        .accessibilityLabel(action.label)
    }

    @ViewBuilder
    private var outline: some View {
        if action.style == .secondary {
            RoundedRectangle(cornerRadius: CGFloat(tokens.borderRadius.mdLg))
                .stroke(Color.cyan, lineWidth: 1)
        }
    }

    private var background: Color {
        switch action.style {
        case .primary: .cyan
        case .secondary: .clear
        case .destructive: ThemeService.shared.error
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
