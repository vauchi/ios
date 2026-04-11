// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Renders a core `DropdownComponent` as a SwiftUI Picker.
/// Selection changes are reported as `UserAction.listItemSelected`.
struct DropdownView: View {
    let component: DropdownComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(component.label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker(component.label, selection: Binding(
                get: { component.selected ?? "" },
                set: { newValue in
                    onAction(.listItemSelected(componentId: component.id, itemId: newValue))
                }
            )) {
                ForEach(component.options) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(component.a11y?.label ?? component.label)
            .accessibilityHint(component.a11y?.hint ?? "")
        }
    }
}
