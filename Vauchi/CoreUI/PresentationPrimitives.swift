// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct PresentationAccessibility: Codable, Equatable {
    let label: String
    let description: String?
}

enum PresentationShortcut: String, Codable {
    case back
    case activatePrimary = "activate_primary"
    case undo
}

enum PresentationActionTone: String, Codable {
    case standard
    case destructive
}

struct PresentationAction: Codable, Equatable, Identifiable {
    let interactionID: String
    let label: String
    let accessibilityLabel: String
    let iconToken: String?
    let enabled: Bool
    let tone: PresentationActionTone
    let shortcut: PresentationShortcut?

    var id: String {
        interactionID
    }

    private enum CodingKeys: String, CodingKey {
        case interactionID = "interaction_id"
        case label
        case accessibilityLabel = "accessibility_label"
        case iconToken = "icon_token"
        case enabled
        case tone
        case shortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactionID = try container.decode(String.self, forKey: .interactionID)
        label = try container.decode(String.self, forKey: .label)
        accessibilityLabel = try container.decode(
            String.self,
            forKey: .accessibilityLabel
        )
        iconToken = try container.decodeIfPresent(String.self, forKey: .iconToken)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        tone = try container.decodeIfPresent(
            PresentationActionTone.self,
            forKey: .tone
        ) ?? .standard
        shortcut = try container.decodeIfPresent(
            PresentationShortcut.self,
            forKey: .shortcut
        )
    }
}

struct PresentationContextBar: Codable, Equatable {
    let back: PresentationAction?
    let navigation: PresentationAction?
    let primary: PresentationAction?
    let secondary: PresentationAction?
}

enum PresentationOverlayKind: String, Codable {
    case navigation
    case actionMenu = "action_menu"
}

struct PresentationOverlay: Codable, Equatable {
    let kind: PresentationOverlayKind
    let title: String?
    let items: [PresentationAction]
}

enum PresentationInputMode: String, Codable {
    case touch
    case pointer
    case keyboard
}

enum PresentationMotion: String, Codable {
    case full
    case reduced
}

enum PresentationWindowClass: String, Codable {
    case compact
    case medium
    case expanded
}

enum PresentationPaneLayout: String, Codable {
    case single
    case split
}

struct PresentationProfile: Codable, Equatable {
    let windowClass: PresentationWindowClass
    let paneLayout: PresentationPaneLayout
    let primarySurface: String
    let detailSurface: String?
    let activeSurface: String

    private enum CodingKeys: String, CodingKey {
        case windowClass = "window_class"
        case paneLayout = "pane_layout"
        case primarySurface = "primary_surface"
        case detailSurface = "detail_surface"
        case activeSurface = "active_surface"
    }
}

enum PresentationSurfaceLayout: String, Codable {
    case scroll
    case fixed
    case pinned
}

struct PresentationTokens: Codable, Equatable {
    let spacingSmall: UInt16
    let spacingMedium: UInt16
    let spacingLarge: UInt16
    let cornerRadius: UInt16
    let minimumTargetSize: UInt16

    private enum CodingKeys: String, CodingKey {
        case spacingSmall = "spacing_small"
        case spacingMedium = "spacing_medium"
        case spacingLarge = "spacing_large"
        case cornerRadius = "corner_radius"
        case minimumTargetSize = "minimum_target_size"
    }
}
