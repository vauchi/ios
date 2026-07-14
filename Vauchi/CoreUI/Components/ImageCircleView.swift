// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
import SwiftUI

/// Renders core's domain-agnostic `Component::ImageCircle`.
struct ImageCircleView: View {
    let component: ImageCircleComponent
    let onAction: (UserAction) -> Void

    /// Scales the initials text with the user's Dynamic Type setting.
    @ScaledMetric(relativeTo: .largeTitle) private var initialsFontSize: CGFloat = 40

    private var editActionId: String? {
        guard component.editable else { return nil }
        return component.editActionId
    }

    var body: some View {
        ZStack {
            imageContent
                .brightness(Double(component.brightness))

            if editActionId != nil {
                editOverlay
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture {
            if let editActionId {
                onAction(.actionPressed(actionId: editActionId))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.a11y?.label ?? component.initials)
        .accessibilityHint(component.a11y?.hint ?? "")
        .accessibilityAddTraits(editActionId == nil ? [] : [.isButton])
    }

    @ViewBuilder
    private var imageContent: some View {
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
                        .font(.system(size: initialsFontSize, weight: .bold))
                        .minimumScaleFactor(0.5)
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
