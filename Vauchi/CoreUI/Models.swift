// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Models.swift
// Decodable types matching core UI JSON output (serde snake_case)
// Maps to: vauchi-core/src/ui/screen.rs, component.rs, action.rs

import Foundation

// MARK: - JSON Decoding Strategy

/// Shared decoder configured for serde snake_case output.
let coreJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

/// Shared encoder for sending UserAction to core.
/// Does NOT use `.convertToSnakeCase` because UserAction's custom `encode(to:)`
/// already emits the correct keys (PascalCase variant names like "TextChanged",
/// snake_case field names like "component_id"). Applying `.convertToSnakeCase`
/// would corrupt variant keys to "text_changed", breaking serde deserialization.
let coreJSONEncoder: JSONEncoder = .init()

// MARK: - ScreenModel

/// Describes a full screen to render.
/// Maps to: `vauchi-core::ui::screen::ScreenModel`
struct ScreenModel: Decodable {
    let screenId: String
    let title: String
    let subtitle: String?
    let components: [Component]
    let actions: [ScreenAction]
    let progress: Progress?
}

/// Step progress indicator.
/// Maps to: `vauchi-core::ui::screen::Progress`
struct Progress: Decodable {
    let currentStep: UInt8
    let totalSteps: UInt8
    let label: String?
}

/// A button or action the user can take on the screen.
/// Maps to: `vauchi-core::ui::screen::ScreenAction`
struct ScreenAction: Decodable, Identifiable {
    let id: String
    let label: String
    let style: ActionStyle
    let enabled: Bool
}

/// Visual style for a screen action.
/// Maps to: `vauchi-core::ui::screen::ActionStyle`
enum ActionStyle: String, Decodable {
    case primary = "Primary"
    case secondary = "Secondary"
    case destructive = "Destructive"
}

// MARK: - Component

/// A UI component that core tells frontends to render.
/// Maps to: `vauchi-core::ui::component::Component`
///
/// Rust serde serializes enums as `{"VariantName": {"field": "value"}}` or
/// `"VariantName"` for unit variants. We use custom `Decodable` to handle this.
enum Component: Decodable {
    case text(TextComponent)
    case textInput(TextInputComponent)
    case toggleList(ToggleListComponent)
    case fieldList(FieldListComponent)
    case cardPreview(CardPreviewComponent)
    case infoPanel(InfoPanelComponent)
    case divider

    init(from decoder: Decoder) throws {
        // Try unit variant first ("Divider")
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self),
           stringValue == "Divider" {
            self = .divider
            return
        }

        // Struct variants: {"VariantName": {...}}
        let container = try decoder.container(keyedBy: VariantKey.self)

        if container.contains(.text) {
            self = try .text(container.decode(TextComponent.self, forKey: .text))
        } else if container.contains(.textInput) {
            self = try .textInput(container.decode(TextInputComponent.self, forKey: .textInput))
        } else if container.contains(.toggleList) {
            self = try .toggleList(container.decode(ToggleListComponent.self, forKey: .toggleList))
        } else if container.contains(.fieldList) {
            self = try .fieldList(container.decode(FieldListComponent.self, forKey: .fieldList))
        } else if container.contains(.cardPreview) {
            self = try .cardPreview(container.decode(CardPreviewComponent.self, forKey: .cardPreview))
        } else if container.contains(.infoPanel) {
            self = try .infoPanel(container.decode(InfoPanelComponent.self, forKey: .infoPanel))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown Component variant"
                )
            )
        }
    }

    private enum VariantKey: String, CodingKey {
        case text = "Text"
        case textInput = "TextInput"
        case toggleList = "ToggleList"
        case fieldList = "FieldList"
        case cardPreview = "CardPreview"
        case infoPanel = "InfoPanel"
    }
}

// MARK: - Component Data Types

struct TextComponent: Decodable {
    let id: String
    let content: String
    let style: TextStyle
}

enum TextStyle: String, Decodable {
    case title = "Title"
    case subtitle = "Subtitle"
    case body = "Body"
    case caption = "Caption"
}

struct TextInputComponent: Decodable {
    let id: String
    let label: String
    let value: String
    let placeholder: String?
    let maxLength: Int?
    let validationError: String?
    let inputType: InputType
}

enum InputType: String, Decodable {
    case text = "Text"
    case phone = "Phone"
    case email = "Email"
}

struct ToggleListComponent: Decodable {
    let id: String
    let label: String
    let items: [ToggleItem]
}

struct ToggleItem: Decodable, Identifiable {
    let id: String
    let label: String
    let selected: Bool
    let subtitle: String?
}

struct FieldListComponent: Decodable {
    let id: String
    let fields: [FieldDisplay]
    let visibilityMode: VisibilityMode
    let availableGroups: [String]
}

enum VisibilityMode: String, Decodable {
    case showHide = "ShowHide"
    case perGroup = "PerGroup"
}

struct FieldDisplay: Decodable, Identifiable {
    let id: String
    let fieldType: String
    let label: String
    let value: String
    let visibility: UiFieldVisibility
}

/// UI-level field visibility state.
/// Serde outputs: `"Shown"`, `"Hidden"`, or `{"Groups": ["Family", ...]}`
enum UiFieldVisibility: Decodable {
    case shown
    case hidden
    case groups([String])

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            switch stringValue {
            case "Shown": self = .shown
            case "Hidden": self = .hidden
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown UiFieldVisibility variant: \(stringValue)"
                    )
                )
            }
            return
        }

        let container = try decoder.container(keyedBy: GroupsKey.self)
        let groups = try container.decode([String].self, forKey: .groups)
        self = .groups(groups)
    }

    private enum GroupsKey: String, CodingKey {
        case groups = "Groups"
    }
}

struct CardPreviewComponent: Decodable {
    let name: String
    let fields: [FieldDisplay]
    let groupViews: [GroupCardView]
    let selectedGroup: String?
}

struct GroupCardView: Decodable, Identifiable {
    let groupName: String
    let displayName: String
    let visibleFields: [FieldDisplay]

    var id: String {
        groupName
    }
}

struct InfoPanelComponent: Decodable {
    let id: String
    let icon: String?
    let title: String
    let items: [InfoItem]
}

struct InfoItem: Decodable, Identifiable {
    let icon: String?
    let title: String
    let detail: String

    var id: String {
        title
    }
}

// MARK: - UserAction (Encodable for sending to core)

/// An action the user performed in the UI.
/// Maps to: `vauchi-core::ui::action::UserAction`
///
/// Uses custom encoding to match serde's `{"VariantName": {...}}` format.
enum UserAction: Encodable {
    case textChanged(componentId: String, value: String)
    case itemToggled(componentId: String, itemId: String)
    case actionPressed(actionId: String)
    case fieldVisibilityChanged(fieldId: String, groupId: String?, visible: Bool)
    case groupViewSelected(groupName: String?)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: VariantKey.self)

        switch self {
        case let .textChanged(componentId, value):
            var nested = container.nestedContainer(keyedBy: TextChangedKeys.self, forKey: .textChanged)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(value, forKey: .value)

        case let .itemToggled(componentId, itemId):
            var nested = container.nestedContainer(keyedBy: ItemToggledKeys.self, forKey: .itemToggled)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(itemId, forKey: .itemId)

        case let .actionPressed(actionId):
            var nested = container.nestedContainer(keyedBy: ActionPressedKeys.self, forKey: .actionPressed)
            try nested.encode(actionId, forKey: .actionId)

        case let .fieldVisibilityChanged(fieldId, groupId, visible):
            var nested = container.nestedContainer(
                keyedBy: FieldVisibilityKeys.self, forKey: .fieldVisibilityChanged
            )
            try nested.encode(fieldId, forKey: .fieldId)
            try nested.encode(groupId, forKey: .groupId)
            try nested.encode(visible, forKey: .visible)

        case let .groupViewSelected(groupName):
            var nested = container.nestedContainer(
                keyedBy: GroupViewSelectedKeys.self, forKey: .groupViewSelected
            )
            try nested.encode(groupName, forKey: .groupName)
        }
    }

    private enum VariantKey: String, CodingKey {
        case textChanged = "TextChanged"
        case itemToggled = "ItemToggled"
        case actionPressed = "ActionPressed"
        case fieldVisibilityChanged = "FieldVisibilityChanged"
        case groupViewSelected = "GroupViewSelected"
    }

    private enum TextChangedKeys: String, CodingKey {
        case componentId = "component_id"
        case value
    }

    private enum ItemToggledKeys: String, CodingKey {
        case componentId = "component_id"
        case itemId = "item_id"
    }

    private enum ActionPressedKeys: String, CodingKey {
        case actionId = "action_id"
    }

    private enum FieldVisibilityKeys: String, CodingKey {
        case fieldId = "field_id"
        case groupId = "group_id"
        case visible
    }

    private enum GroupViewSelectedKeys: String, CodingKey {
        case groupName = "group_name"
    }
}

// MARK: - ActionResult

/// The result of handling a user action.
/// Maps to: `vauchi-core::ui::action::ActionResult`
enum ActionResult: Decodable {
    case updateScreen(ScreenModel)
    case navigateTo(ScreenModel)
    case validationError(componentId: String, message: String)
    case complete

    init(from decoder: Decoder) throws {
        // Unit variant: "Complete"
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self),
           stringValue == "Complete" {
            self = .complete
            return
        }

        let container = try decoder.container(keyedBy: VariantKey.self)

        if container.contains(.updateScreen) {
            self = try .updateScreen(container.decode(ScreenModel.self, forKey: .updateScreen))
        } else if container.contains(.navigateTo) {
            self = try .navigateTo(container.decode(ScreenModel.self, forKey: .navigateTo))
        } else if container.contains(.validationError) {
            let error = try container.decode(ValidationErrorData.self, forKey: .validationError)
            self = .validationError(componentId: error.componentId, message: error.message)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown ActionResult variant"
                )
            )
        }
    }

    private enum VariantKey: String, CodingKey {
        case updateScreen = "UpdateScreen"
        case navigateTo = "NavigateTo"
        case validationError = "ValidationError"
    }

    private struct ValidationErrorData: Decodable {
        let componentId: String
        let message: String
    }
}
