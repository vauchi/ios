// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AvatarPreviewView.swift
// Renders an AvatarPreview component from core UI

import SwiftUI

/// Renders a core `Component::AvatarPreview` as a circular avatar with optional edit overlay.
struct AvatarPreviewView: View {
    let component: AvatarPreviewComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        ZStack {
            avatarContent
                .brightness(Double(component.brightness))

            if component.editable {
                editOverlay
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture {
            if component.editable {
                onAction(.actionPressed(actionId: "edit_avatar"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.a11y?.label ?? "Avatar: \(component.initials)")
        .accessibilityHint(component.a11y?.hint ?? (component.editable ? "Tap to edit avatar" : ""))
        .accessibilityAddTraits(component.editable ? [.isButton] : [])
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let imageData = component.imageData,
           let uiImage = UIImage(data: Data(imageData)) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
        } else {
            Circle()
                .fill(backgroundGradient)
                .overlay(
                    Text(component.initials)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }

    private var editOverlay: some View {
        Circle()
            .fill(Color.black.opacity(0.3))
            .overlay(
                Image(systemName: "camera")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            )
    }

    private var backgroundGradient: LinearGradient {
        if let bgColor = component.bgColor, bgColor.count >= 3 {
            let color = Color(
                red: Double(bgColor[0]) / 255.0,
                green: Double(bgColor[1]) / 255.0,
                blue: Double(bgColor[2]) / 255.0
            )
            return LinearGradient(
                colors: [color, color.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [.cyan, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
