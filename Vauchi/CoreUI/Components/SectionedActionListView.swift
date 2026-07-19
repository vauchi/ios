// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Renders Component::SectionedActionList — grouped menu with native sections.
// Distinct from ActionListView (flat menu).
// Per shell-purity investigation 2026-05-28.

import CoreUIModels
import SwiftUI

/// Renders a core `Component::SectionedActionList` as grouped sections of
/// tappable rows.
///
/// **Must NOT use a SwiftUI `List`.** `ScreenRendererView` already wraps
/// every component in a `ScrollView`, and a `List` nested in a `ScrollView`
/// has no intrinsic height — it collapses to zero rows, leaving the screen
/// blank (the iOS More-tab-empty bug, `problems/2026-06-02-ios-sectioned-
/// action-list-empty`). Like `ActionListView`, this renders `VStack` +
/// `ForEach` with hand-drawn section headers / dividers so it lays out
/// inside the outer `ScrollView`.
struct SectionedActionListView: View {
    let component: SectionedActionListComponent
    let onAction: (UserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(component.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.label)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            SectionedActionRowView(
                                componentId: component.id,
                                sectionId: section.id,
                                item: item,
                                onAction: onAction
                            )
                            if index < section.items.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // NO container identifier here: when the parent VStack carries
        // `accessibilityIdentifier(component.id)`, XCTest merges every
        // child row under the PARENT's id and the rows' own
        // identifiers never surface
        // (problems/2026-07-18-ios-sectioned-action-rows-not-addressable).
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
        HStack(spacing: 12) {
            leadingIcon
            Text(item.label).foregroundColor(.primary)
            Spacer()
            trailingDetail
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        // NOTE: rows are individually addressable via
        // `\(componentId).\(sectionId).\(item.id)`. onTapGesture is used
        // instead of Button(plain): the latter's action is unreliable
        // under XCTest for custom-content rows
        // (problems/2026-07-18-ios-sectioned-action-rows-not-addressable).
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("\(componentId).\(sectionId).\(item.id)")
        .accessibilityLabel(item.a11y?.label ?? item.label)
        .accessibilityHint(item.a11y?.hint ?? "")
        .accessibilityAddTraits(.isButton)
    }

    private func tap() {
        onAction(.listItemSelected(componentId: componentId, itemId: item.id))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let icon = item.icon {
            // TODO(HUMBLE): [T, P1] frontend treats core icon token as a raw SF Symbol name;
            // use the platform icon-token mapper (see _private problem record 2026-07-06-mobile-domain-shell-violations).
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
