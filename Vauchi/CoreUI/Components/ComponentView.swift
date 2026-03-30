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

        case let .contactList(contactListComponent):
            ContactListView(component: contactListComponent, onAction: onAction)

        case let .settingsGroup(settingsGroupComponent):
            SettingsGroupView(component: settingsGroupComponent, onAction: onAction)

        case let .actionList(actionListComponent):
            ActionListView(component: actionListComponent, onAction: onAction)

        case let .statusIndicator(statusComponent):
            StatusIndicatorView(component: statusComponent)

        case let .pinInput(pinComponent):
            PinInputView(component: pinComponent, onAction: onAction)

        case let .qrCode(qrComponent):
            QrCodeView(component: qrComponent, onAction: onAction)

        case let .confirmationDialog(dialogComponent):
            ConfirmationDialogView(component: dialogComponent, onAction: onAction)

        case let .showToast(toastComponent):
            // Toast rendering is handled at the screen level, not inline
            EmptyView()
                .onAppear {
                    print("ComponentView: ShowToast should be handled at screen level: \(toastComponent.message)")
                }

        case let .inlineConfirm(confirmComponent):
            InlineConfirmView(component: confirmComponent, onAction: onAction)

        case let .editableText(editableComponent):
            EditableTextView(component: editableComponent, onAction: onAction)

        case let .banner(bannerComponent):
            BannerView(component: bannerComponent, onAction: onAction)

        case .divider:
            DividerView()

        case .unknown:
            // Core sent a component type this shell doesn't know about.
            // Render as invisible — the screen still works, just missing
            // one component. User can update the app for full experience.
            EmptyView()
        }
    }
}
