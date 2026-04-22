// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SliderComponentView.swift
// Renders a Slider component from core UI

import CoreUIModels
import SwiftUI

/// Renders a core `Component::Slider` as a SwiftUI Slider with optional min/max icons.
struct SliderComponentView: View {
    let component: SliderComponent
    let onAction: (UserAction) -> Void

    @State private var localValue: Float = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(component.label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                if let minIcon = component.minIcon {
                    Image(systemName: minIcon)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }

                Slider(
                    value: $localValue,
                    in: component.min ... component.max,
                    step: component.step
                )
                .onChange(of: localValue) { newValue in
                    let valueMilli = Int32(newValue * 1000)
                    onAction(.sliderChanged(componentId: component.id, valueMilli: valueMilli))
                }

                if let maxIcon = component.maxIcon {
                    Image(systemName: maxIcon)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .onAppear {
            localValue = component.value
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(component.a11y?.label ?? component.label)
        .accessibilityHint(component.a11y?.hint ?? "")
        .accessibilityIdentifier(component.id)
    }
}
