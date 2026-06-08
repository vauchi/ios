// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Routes a Component enum to the appropriate SwiftUI view

import CoreUIModels
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

        case let .preview(previewComponent):
            PreviewView(component: previewComponent, onAction: onAction)

        case let .infoPanel(panelComponent):
            InfoPanelView(component: panelComponent)

        case let .list(listComponent):
            ListView(component: listComponent, onAction: onAction)

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
                    #if DEBUG
                        print("ComponentView: ShowToast should be handled at screen level: \(toastComponent.message)")
                    #endif
                }

        case let .inlineConfirm(confirmComponent):
            InlineConfirmView(component: confirmComponent, onAction: onAction)

        case let .editableText(editableComponent):
            EditableTextView(component: editableComponent, onAction: onAction)

        case let .banner(bannerComponent):
            BannerView(component: bannerComponent, onAction: onAction)

        case let .indicator(indicatorComponent):
            IndicatorView(component: indicatorComponent, onAction: onAction)

        case let .sectionedActionList(sectionedComponent):
            SectionedActionListView(component: sectionedComponent, onAction: onAction)

        case let .dropdown(dropdownComponent):
            DropdownView(component: dropdownComponent, onAction: onAction)

        case let .avatarPreview(avatarComponent):
            AvatarPreviewView(component: avatarComponent, onAction: onAction)

        case let .slider(sliderComponent):
            SliderComponentView(component: sliderComponent, onAction: onAction)

        case .divider:
            DividerView()

        case let .row(rowComponent):
            // Horizontal container: render children left-to-right. Each
            // child is width-bounded with an equal flex slice (mirrors
            // Android's per-child `Modifier.weight(1f)`), so a child that
            // fills its width internally (e.g. an ActionList with trailing
            // Spacers) takes only its slice instead of overflowing and
            // overlapping the preview.
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(rowComponent.items.enumerated()), id: \.offset) { _, child in
                    ComponentView(component: child, onAction: onAction)
                        .frame(maxWidth: .infinity)
                }
            }

        case .unknown:
            // Core sent a component type this shell doesn't know about.
            // Render as invisible — the screen still works, just missing
            // one component. User can update the app for full experience.
            EmptyView()
        }
    }
}
