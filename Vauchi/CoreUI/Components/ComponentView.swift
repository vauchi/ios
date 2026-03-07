// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ComponentView.swift
// Routes a Component enum to the appropriate SwiftUI view

import SwiftUI

/// Routes a core `Component` to the appropriate SwiftUI view.
struct ComponentView: View {
    let component: Component
    let onAction: (UserAction) -> Void

    var body: some View {
        switch component {
        case let .text(textComponent):
            TextComponentView(component: textComponent)

        case let .textInput(inputComponent):
            TextInputView(component: inputComponent, onAction: onAction)

        case let .toggleList(toggleComponent):
            ToggleListView(component: toggleComponent, onAction: onAction)

        case let .fieldList(fieldComponent):
            FieldListView(component: fieldComponent, onAction: onAction)

        case let .cardPreview(previewComponent):
            CardPreviewView(component: previewComponent, onAction: onAction)

        case let .infoPanel(panelComponent):
            InfoPanelView(component: panelComponent)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }
}
