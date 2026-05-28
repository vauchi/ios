// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// SectionedActionListView.swift
// Renders Component::SectionedActionList — grouped menu with native sections.
// Distinct from ActionListView (flat menu).
// Per shell-purity investigation 2026-05-28.

import CoreUIModels
import SwiftUI

/// Renders a core `Component::SectionedActionList` as a native SwiftUI
/// list with one `Section` per group. iOS's native idiom — flat
/// renderers that ignored a section grouping would downgrade UX from
/// "structured menu" to "flat dump", so the discriminant lives at
/// variant level.
struct SectionedActionListView: View {
    let component: SectionedActionListComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        List {
            ForEach(component.sections) { section in
                Section(section.label) {
                    ForEach(section.items) { item in
                        SectionedActionRowView(
                            componentId: component.id,
                            sectionId: section.id,
                            item: item,
                            onAction: onAction
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(component.id)
    }
}

/// One row inside a `SectionedActionListView`. Extracted so SwiftUI's
/// type checker doesn't time out on the nested optional-icon /
/// optional-detail HStack.
private struct SectionedActionRowView: View {
    let componentId: String
    let sectionId: String
    let item: ActionListItem
    let onAction: (UserAction) -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                leadingIcon
                Text(item.label).foregroundColor(.primary)
                Spacer()
                trailingDetail
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("\(componentId).\(sectionId).\(item.id)")
        .accessibilityLabel(item.a11y?.label ?? item.label)
        .accessibilityHint(item.a11y?.hint ?? "")
    }

    private func tap() {
        onAction(.listItemSelected(componentId: componentId, itemId: item.id))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let icon = item.icon {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
        }
    }

    @ViewBuilder
    private var trailingDetail: some View {
        if let detail = item.detail {
            Text(detail)
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }
}
