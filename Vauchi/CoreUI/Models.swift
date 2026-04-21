// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Models.swift
// Decodable types matching core UI JSON output (serde snake_case)
// Maps to: vauchi-core/src/ui/screen.rs, component.rs, action.rs

import Foundation
import SwiftUI

// MARK: - Design Token Environment

/// SwiftUI environment key for injecting design tokens into the view hierarchy.
private struct DesignTokensKey: EnvironmentKey {
    static let defaultValue: DesignTokens = .defaults
}

extension EnvironmentValues {
    var designTokens: DesignTokens {
        get { self[DesignTokensKey.self] }
        set { self[DesignTokensKey.self] = newValue }
    }
}

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

// MARK: - Design Tokens

/// Layout tokens for consistent cross-platform rendering.
/// Maps to: `vauchi-core::theme::DesignTokens`
struct DesignTokens: Decodable {
    let spacing: SpacingTokens
    let spacingDirection: SpacingDirectionTokens
    let typography: TypographyTokens
    let borderRadius: BorderRadiusTokens
    let touchTarget: TouchTargetTokens
    let motion: MotionTokens

    static let defaults = DesignTokens(
        spacing: SpacingTokens(xs: 4, sm: 8, smMd: 12, md: 16, lg: 24, xl: 32),
        spacingDirection: SpacingDirectionTokens(contentStart: 16, contentEnd: 16, listItemStart: 8, listItemEnd: 8, listItemInlineStart: 12, listItemInlineEnd: 12),
        typography: TypographyTokens(titleSize: 24, subtitleSize: 18, bodySize: 16, captionSize: 14),
        borderRadius: BorderRadiusTokens(sm: 4, md: 8, mdLg: 12, lg: 16),
        touchTarget: TouchTargetTokens(minimum: 44),
        motion: MotionTokens(enterDurationMs: 200, exitDurationMs: 150, emphasisDurationMs: 300)
    )
}

struct SpacingTokens: Decodable {
    let xs: UInt16
    let sm: UInt16
    let smMd: UInt16
    let md: UInt16
    let lg: UInt16
    let xl: UInt16

    init(xs: UInt16, sm: UInt16, smMd: UInt16 = 12, md: UInt16, lg: UInt16, xl: UInt16) {
        self.xs = xs
        self.sm = sm
        self.smMd = smMd
        self.md = md
        self.lg = lg
        self.xl = xl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xs = try container.decode(UInt16.self, forKey: .xs)
        sm = try container.decode(UInt16.self, forKey: .sm)
        smMd = try container.decodeIfPresent(UInt16.self, forKey: .smMd) ?? 12
        md = try container.decode(UInt16.self, forKey: .md)
        lg = try container.decode(UInt16.self, forKey: .lg)
        xl = try container.decode(UInt16.self, forKey: .xl)
    }

    private enum CodingKeys: String, CodingKey {
        case xs, sm, smMd, md, lg, xl
    }
}

struct SpacingDirectionTokens: Decodable {
    let contentStart: UInt16
    let contentEnd: UInt16
    let listItemStart: UInt16
    let listItemEnd: UInt16
    let listItemInlineStart: UInt16
    let listItemInlineEnd: UInt16
}

struct TypographyTokens: Decodable {
    let titleSize: UInt16
    let subtitleSize: UInt16
    let bodySize: UInt16
    let captionSize: UInt16
}

struct BorderRadiusTokens: Decodable {
    let sm: UInt16
    let md: UInt16
    let mdLg: UInt16
    let lg: UInt16
}

struct TouchTargetTokens: Decodable {
    let minimum: UInt16
}

struct MotionTokens: Decodable {
    let enterDurationMs: UInt16
    let exitDurationMs: UInt16
    let emphasisDurationMs: UInt16
}

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
    let tokens: DesignTokens

    private enum CodingKeys: String, CodingKey {
        case screenId, title, subtitle, components, actions, progress, tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenId = try container.decode(String.self, forKey: .screenId)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        components = try container.decode([Component].self, forKey: .components)
        actions = try container.decode([ScreenAction].self, forKey: .actions)
        progress = try container.decodeIfPresent(Progress.self, forKey: .progress)
        tokens = try container.decodeIfPresent(DesignTokens.self, forKey: .tokens) ?? .defaults
    }
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
    case contactList(ContactListComponent)
    case settingsGroup(SettingsGroupComponent)
    case actionList(ActionListComponent)
    case statusIndicator(StatusIndicatorComponent)
    case pinInput(PinInputComponent)
    case qrCode(QrCodeComponent)
    case confirmationDialog(ConfirmationDialogComponent)
    case showToast(ShowToastComponent)
    case inlineConfirm(InlineConfirmComponent)
    case editableText(EditableTextComponent)
    case banner(BannerComponent)
    case dropdown(DropdownComponent)
    case avatarPreview(AvatarPreviewComponent)
    case slider(SliderComponent)
    case divider
    /// Unknown component from a newer core version — render as empty space.
    /// Prevents crash when core adds new component types that this shell
    /// version doesn't know about. See: design-as-code-plan Phase 2b.
    case unknown

    // swiftlint:disable:next cyclomatic_complexity
    init(from decoder: Decoder) throws {
        // Try unit variant first ("Divider" or any unknown string)
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            if stringValue == "Divider" {
                self = .divider
            } else {
                // Unknown unit variant — degrade gracefully
                self = .unknown
            }
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
        } else if container.contains(.contactList) {
            self = try .contactList(container.decode(ContactListComponent.self, forKey: .contactList))
        } else if container.contains(.settingsGroup) {
            self = try .settingsGroup(container.decode(SettingsGroupComponent.self, forKey: .settingsGroup))
        } else if container.contains(.actionList) {
            self = try .actionList(container.decode(ActionListComponent.self, forKey: .actionList))
        } else if container.contains(.statusIndicator) {
            self = try .statusIndicator(container.decode(StatusIndicatorComponent.self, forKey: .statusIndicator))
        } else if container.contains(.pinInput) {
            self = try .pinInput(container.decode(PinInputComponent.self, forKey: .pinInput))
        } else if container.contains(.qrCode) {
            self = try .qrCode(container.decode(QrCodeComponent.self, forKey: .qrCode))
        } else if container.contains(.confirmationDialog) {
            self = try .confirmationDialog(
                container.decode(ConfirmationDialogComponent.self, forKey: .confirmationDialog)
            )
        } else if container.contains(.showToast) {
            self = try .showToast(container.decode(ShowToastComponent.self, forKey: .showToast))
        } else if container.contains(.inlineConfirm) {
            self = try .inlineConfirm(container.decode(InlineConfirmComponent.self, forKey: .inlineConfirm))
        } else if container.contains(.editableText) {
            self = try .editableText(container.decode(EditableTextComponent.self, forKey: .editableText))
        } else if container.contains(.banner) {
            self = try .banner(container.decode(BannerComponent.self, forKey: .banner))
        } else if container.contains(.dropdown) {
            self = try .dropdown(container.decode(DropdownComponent.self, forKey: .dropdown))
        } else if container.contains(.avatarPreview) {
            self = try .avatarPreview(container.decode(AvatarPreviewComponent.self, forKey: .avatarPreview))
        } else if container.contains(.slider) {
            self = try .slider(container.decode(SliderComponent.self, forKey: .slider))
        } else {
            // Unknown struct variant — core is newer than this shell.
            // Degrade gracefully instead of crashing.
            self = .unknown
        }
    }

    private enum VariantKey: String, CodingKey {
        case text = "Text"
        case textInput = "TextInput"
        case toggleList = "ToggleList"
        case fieldList = "FieldList"
        case cardPreview = "CardPreview"
        case infoPanel = "InfoPanel"
        case contactList = "ContactList"
        case settingsGroup = "SettingsGroup"
        case actionList = "ActionList"
        case statusIndicator = "StatusIndicator"
        case pinInput = "PinInput"
        case qrCode = "QrCode"
        case confirmationDialog = "ConfirmationDialog"
        case showToast = "ShowToast"
        case inlineConfirm = "InlineConfirm"
        case editableText = "EditableText"
        case banner = "Banner"
        case dropdown = "Dropdown"
        case avatarPreview = "AvatarPreview"
        case slider = "Slider"
    }
}

// MARK: - A11y

/// Core-driven accessibility metadata attached to components.
/// Maps to: `vauchi-core::ui::component::A11y`
struct A11y: Decodable {
    let label: String?
    let hint: String?
    let role: String?
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
    var a11y: A11y?
}

enum InputType: String, Decodable {
    case text = "Text"
    case phone = "Phone"
    case email = "Email"
    case password = "Password"
}

struct ToggleListComponent: Decodable {
    let id: String
    let label: String
    let items: [ToggleItem]
    var a11y: A11y?
}

struct ToggleItem: Decodable, Identifiable {
    let id: String
    let label: String
    let selected: Bool
    let subtitle: String?
    var a11y: A11y?
}

struct FieldListComponent: Decodable {
    let id: String
    let fields: [FieldDisplay]
    let visibilityMode: VisibilityMode
    let availableGroups: [String]
    var a11y: A11y?
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
    var a11y: A11y?
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
    let avatarData: [UInt8]?
    let fields: [FieldDisplay]
    let groupViews: [GroupCardView]
    let selectedGroup: String?
    var a11y: A11y?
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
    var a11y: A11y?
}

struct InfoItem: Decodable, Identifiable {
    let icon: String?
    let title: String
    let detail: String

    var id: String {
        title
    }
}

// MARK: - ContactList Component

struct ContactListComponent: Decodable {
    let id: String
    let contacts: [ContactItem]
    let searchable: Bool
}

struct ContactItem: Decodable, Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let avatarInitials: String
    let status: String?
    var searchableFields: [String] = []
    var actions: [ListItemAction] = []
    var a11y: A11y?

    /// Default Decodable synthesis matches: `coreJSONDecoder` above sets
    /// `.convertFromSnakeCase`, so wire keys like `avatar_initials` and
    /// `searchable_fields` are mapped automatically to their camelCase
    /// property names here. The custom init only exists so new fields
    /// (`searchableFields`, `actions`) default to empty when absent
    /// from legacy fixtures or older engine versions.
    private enum CodingKeys: String, CodingKey {
        case id, name, subtitle, avatarInitials, status, searchableFields, actions, a11y
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        avatarInitials = try c.decode(String.self, forKey: .avatarInitials)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        searchableFields = (try? c.decode([String].self, forKey: .searchableFields)) ?? []
        actions = (try? c.decode([ListItemAction].self, forKey: .actions)) ?? []
        a11y = try? c.decode(A11y.self, forKey: .a11y)
    }
}

/// Semantic classification for a per-row action. Mirrors
/// `vauchi-core::ui::component::ListItemActionKind`. Serialized snake_case.
enum ListItemActionKind: String, Decodable {
    case archive
    case unarchive
    case hide
    case unhide
    case delete
    case undelete
    case custom
    /// Forward-compat fallback for kinds added in a newer core.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ListItemActionKind(rawValue: raw) ?? .unknown
    }
}

/// A per-row swipe/context-menu action produced by core. Mirrors
/// `vauchi-core::ui::component::ListItemAction`.
struct ListItemAction: Decodable, Identifiable {
    let id: String
    let label: String
    let kind: ListItemActionKind
    let destructive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, label, kind, destructive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decode(ListItemActionKind.self, forKey: .kind)
        destructive = (try? c.decode(Bool.self, forKey: .destructive)) ?? false
    }
}

// MARK: - SettingsGroup Component

struct SettingsGroupComponent: Decodable {
    let id: String
    let label: String
    let items: [SettingsItem]
}

struct SettingsItem: Decodable, Identifiable {
    let id: String
    let label: String
    let kind: SettingsItemKind
    var a11y: A11y?
}

enum SettingsItemKind: Decodable {
    case toggle(enabled: Bool)
    case value(value: String)
    case link(detail: String?)
    case destructive(label: String)
    case unknown

    init(from decoder: Decoder) throws {
        // Serde produces: {"Toggle": {"enabled": true}}, etc.
        let container = try decoder.container(keyedBy: VariantKey.self)
        if container.contains(.toggle) {
            let data = try container.decode(ToggleData.self, forKey: .toggle)
            self = .toggle(enabled: data.enabled)
        } else if container.contains(.value) {
            let data = try container.decode(ValueData.self, forKey: .value)
            self = .value(value: data.value)
        } else if container.contains(.link) {
            let data = try container.decode(LinkData.self, forKey: .link)
            self = .link(detail: data.detail)
        } else if container.contains(.destructive) {
            let data = try container.decode(DestructiveData.self, forKey: .destructive)
            self = .destructive(label: data.label)
        } else {
            // Unknown settings item kind from newer core — show as link
            self = .unknown
        }
    }

    private enum VariantKey: String, CodingKey {
        case toggle = "Toggle"
        case value = "Value"
        case link = "Link"
        case destructive = "Destructive"
    }

    private struct ToggleData: Decodable { let enabled: Bool }
    private struct ValueData: Decodable { let value: String }
    private struct LinkData: Decodable { let detail: String? }
    private struct DestructiveData: Decodable { let label: String }
}

// MARK: - ActionList Component

struct ActionListComponent: Decodable {
    let id: String
    let items: [ActionListItem]
}

struct ActionListItem: Decodable, Identifiable {
    let id: String
    let label: String
    let icon: String?
    let detail: String?
    var a11y: A11y?
}

// MARK: - StatusIndicator Component

struct StatusIndicatorComponent: Decodable {
    let id: String
    let icon: String?
    let title: String
    let detail: String?
    let status: Status
    var a11y: A11y?
}

enum Status: String, Decodable {
    case pending = "Pending"
    case inProgress = "InProgress"
    case success = "Success"
    case failed = "Failed"
    case warning = "Warning"
}

// MARK: - PinInput Component

struct PinInputComponent: Decodable {
    let id: String
    let label: String
    let length: Int
    let masked: Bool
    let validationError: String?
    var a11y: A11y?
}

// MARK: - QrCode Component

struct QrCodeComponent: Decodable {
    let id: String
    let data: String
    let mode: QrMode
    let label: String?
    var a11y: A11y?
}

enum QrMode: String, Decodable {
    case display = "Display"
    case scan = "Scan"
}

// MARK: - ConfirmationDialog Component

struct ConfirmationDialogComponent: Decodable {
    let id: String
    let title: String
    let message: String
    let confirmText: String
    let destructive: Bool
}

// MARK: - ShowToast Component

struct ShowToastComponent: Decodable {
    let id: String
    let message: String
    let undoActionId: String?
    let durationMs: UInt32
}

// MARK: - InlineConfirm Component

struct InlineConfirmComponent: Decodable {
    let id: String
    let warning: String
    let confirmText: String
    let cancelText: String
    let destructive: Bool
    var a11y: A11y?
}

// MARK: - EditableText Component

struct EditableTextComponent: Decodable {
    let id: String
    let label: String
    let value: String
    let editing: Bool
    let validationError: String?
    var a11y: A11y?
}

// MARK: - Banner Component

struct BannerComponent: Decodable {
    let text: String
    let actionLabel: String
    let actionId: String
    var a11y: A11y?
}

// MARK: - Dropdown Component

struct DropdownComponent: Decodable {
    let id: String
    let label: String
    let selected: String?
    let options: [DropdownOption]
    var a11y: A11y?
}

struct DropdownOption: Decodable, Identifiable {
    let id: String
    let label: String
}

// MARK: - AvatarPreview Component

struct AvatarPreviewComponent: Decodable {
    let id: String
    let imageData: [UInt8]?
    let initials: String
    let bgColor: [UInt8]?
    let brightness: Float
    let editable: Bool
    let a11y: A11y?
}

// MARK: - Slider Component

struct SliderComponent: Decodable {
    let id: String
    let label: String
    let value: Float
    let min: Float
    let max: Float
    let step: Float
    let minIcon: String?
    let maxIcon: String?
    let a11y: A11y?
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
    case searchChanged(componentId: String, query: String)
    case listItemSelected(componentId: String, itemId: String)
    case listItemAction(componentId: String, itemId: String, actionId: String)
    case settingsToggled(componentId: String, itemId: String)
    case undoPressed(actionId: String)
    case sliderChanged(componentId: String, valueMilli: Int32)

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
            var nested = container.nestedContainer(keyedBy: FieldVisibilityKeys.self, forKey: .fieldVisibilityChanged)
            try nested.encode(fieldId, forKey: .fieldId)
            try nested.encodeIfPresent(groupId, forKey: .groupId)
            try nested.encode(visible, forKey: .visible)

        case let .groupViewSelected(groupName):
            var nested = container.nestedContainer(keyedBy: GroupViewSelectedKeys.self, forKey: .groupViewSelected)
            try nested.encodeIfPresent(groupName, forKey: .groupName)

        case let .searchChanged(componentId, query):
            var nested = container.nestedContainer(keyedBy: SearchChangedKeys.self, forKey: .searchChanged)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(query, forKey: .query)

        case let .listItemSelected(componentId, itemId):
            var nested = container.nestedContainer(keyedBy: ListItemSelectedKeys.self, forKey: .listItemSelected)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(itemId, forKey: .itemId)

        case let .listItemAction(componentId, itemId, actionId):
            var nested = container.nestedContainer(keyedBy: ListItemActionKeys.self, forKey: .listItemAction)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(itemId, forKey: .itemId)
            try nested.encode(actionId, forKey: .actionId)

        case let .settingsToggled(componentId, itemId):
            var nested = container.nestedContainer(keyedBy: SettingsToggledKeys.self, forKey: .settingsToggled)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(itemId, forKey: .itemId)

        case let .undoPressed(actionId):
            var nested = container.nestedContainer(keyedBy: UndoPressedKeys.self, forKey: .undoPressed)
            try nested.encode(actionId, forKey: .actionId)

        case let .sliderChanged(componentId, valueMilli):
            var nested = container.nestedContainer(keyedBy: SliderChangedKeys.self, forKey: .sliderChanged)
            try nested.encode(componentId, forKey: .componentId)
            try nested.encode(valueMilli, forKey: .valueMilli)
        }
    }

    private enum VariantKey: String, CodingKey {
        case textChanged = "TextChanged"
        case itemToggled = "ItemToggled"
        case actionPressed = "ActionPressed"
        case fieldVisibilityChanged = "FieldVisibilityChanged"
        case groupViewSelected = "GroupViewSelected"
        case searchChanged = "SearchChanged"
        case listItemSelected = "ListItemSelected"
        case listItemAction = "ListItemAction"
        case settingsToggled = "SettingsToggled"
        case undoPressed = "UndoPressed"
        case sliderChanged = "SliderChanged"
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

    private enum SearchChangedKeys: String, CodingKey {
        case componentId = "component_id"
        case query
    }

    private enum ListItemSelectedKeys: String, CodingKey {
        case componentId = "component_id"
        case itemId = "item_id"
    }

    private enum ListItemActionKeys: String, CodingKey {
        case componentId = "component_id"
        case itemId = "item_id"
        case actionId = "action_id"
    }

    private enum SettingsToggledKeys: String, CodingKey {
        case componentId = "component_id"
        case itemId = "item_id"
    }

    private enum UndoPressedKeys: String, CodingKey {
        case actionId = "action_id"
    }

    private enum SliderChangedKeys: String, CodingKey {
        case componentId = "component_id"
        case valueMilli = "value_milli"
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
    case startDeviceLink
    case startBackupImport
    case openContact(contactId: String)
    case editContact(contactId: String)
    case openUrl(url: String)
    case showAlert(title: String, message: String)
    case requestCamera
    case openEntryDetail(fieldId: String)
    case showToast(message: String, undoActionId: String?)
    case wipeComplete
    case exchangeCommands(commands: [ExchangeCommandDTO])
    case showFormDialog(dialogType: String, contextId: String?)
    case previewAs(contactId: String)
    case unknown

    init(from decoder: Decoder) throws {
        // Unit variants: "Complete", "StartDeviceLink", etc.
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            switch stringValue {
            case "Complete": self = .complete
            case "StartDeviceLink": self = .startDeviceLink
            case "StartBackupImport": self = .startBackupImport
            case "RequestCamera": self = .requestCamera
            case "WipeComplete": self = .wipeComplete
            default: self = .unknown
            }
            return
        }

        // Struct variants: {"VariantName": {...}}
        let container = try decoder.container(keyedBy: VariantKey.self)

        if container.contains(.updateScreen) {
            self = try .updateScreen(container.decode(ScreenModel.self, forKey: .updateScreen))
        } else if container.contains(.navigateTo) {
            self = try .navigateTo(container.decode(ScreenModel.self, forKey: .navigateTo))
        } else if container.contains(.validationError) {
            let error = try container.decode(ValidationErrorData.self, forKey: .validationError)
            self = .validationError(componentId: error.componentId, message: error.message)
        } else if container.contains(.openContact) {
            let data = try container.decode(OpenContactData.self, forKey: .openContact)
            self = .openContact(contactId: data.contactId)
        } else if container.contains(.editContact) {
            let data = try container.decode(EditContactData.self, forKey: .editContact)
            self = .editContact(contactId: data.contactId)
        } else if container.contains(.openUrl) {
            let data = try container.decode(OpenUrlData.self, forKey: .openUrl)
            self = .openUrl(url: data.url)
        } else if container.contains(.showAlert) {
            let data = try container.decode(ShowAlertData.self, forKey: .showAlert)
            self = .showAlert(title: data.title, message: data.message)
        } else if container.contains(.openEntryDetail) {
            let data = try container.decode(OpenEntryDetailData.self, forKey: .openEntryDetail)
            self = .openEntryDetail(fieldId: data.fieldId)
        } else if container.contains(.showToast) {
            let data = try container.decode(ShowToastData.self, forKey: .showToast)
            self = .showToast(message: data.message, undoActionId: data.undoActionId)
        } else if container.contains(.exchangeCommands) {
            let data = try container.decode(ExchangeCommandsData.self, forKey: .exchangeCommands)
            self = .exchangeCommands(commands: data.commands)
        } else if container.contains(.showFormDialog) {
            let data = try container.decode(ShowFormDialogData.self, forKey: .showFormDialog)
            self = .showFormDialog(dialogType: data.dialogType, contextId: data.contextId)
        } else if container.contains(.previewAs) {
            let data = try container.decode(PreviewAsData.self, forKey: .previewAs)
            self = .previewAs(contactId: data.contactId)
        } else {
            self = .unknown
        }
    }

    private enum VariantKey: String, CodingKey {
        case updateScreen = "UpdateScreen"
        case navigateTo = "NavigateTo"
        case validationError = "ValidationError"
        case openContact = "OpenContact"
        case editContact = "EditContact"
        case openUrl = "OpenUrl"
        case showAlert = "ShowAlert"
        case openEntryDetail = "OpenEntryDetail"
        case showToast = "ShowToast"
        case exchangeCommands = "ExchangeCommands"
        case showFormDialog = "ShowFormDialog"
        case previewAs = "PreviewAs"
    }

    private struct ValidationErrorData: Decodable {
        let componentId: String
        let message: String
    }

    private struct OpenContactData: Decodable {
        let contactId: String
    }

    private struct EditContactData: Decodable {
        let contactId: String
    }

    private struct OpenUrlData: Decodable {
        let url: String
    }

    private struct ShowAlertData: Decodable {
        let title: String
        let message: String
    }

    private struct OpenEntryDetailData: Decodable {
        let fieldId: String
    }

    private struct ShowToastData: Decodable {
        let message: String
        let undoActionId: String?
    }

    private struct ExchangeCommandsData: Decodable {
        let commands: [ExchangeCommandDTO]
    }

    private struct ShowFormDialogData: Decodable {
        let dialogType: String
        let contextId: String?
    }

    private struct PreviewAsData: Decodable {
        let contactId: String
    }
}

/// DTO for exchange commands from core (ADR-031).
/// Maps to: `vauchi-core::exchange::command::ExchangeCommand`
enum ExchangeCommandDTO: Decodable {
    case qrDisplay(data: String)
    case qrRequestScan
    case bleStartAdvertising(serviceUuid: String, payload: [UInt8])
    case bleStartScanning(serviceUuid: String)
    case bleConnect(deviceId: String)
    case bleWriteCharacteristic(uuid: String, data: [UInt8])
    case bleReadCharacteristic(uuid: String)
    case bleDisconnect
    case nfcActivate(payload: [UInt8])
    case nfcDeactivate
    case audioEmitChallenge(data: [UInt8])
    case audioListenForResponse(timeoutMs: UInt64)
    case audioStop
    case imagePickFromLibrary
    case imageCaptureFromCamera
    case imagePickFromFile
    case unknown

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            switch stringValue {
            case "QrRequestScan": self = .qrRequestScan
            case "BleDisconnect": self = .bleDisconnect
            case "NfcDeactivate": self = .nfcDeactivate
            case "AudioStop": self = .audioStop
            case "ImagePickFromLibrary": self = .imagePickFromLibrary
            case "ImageCaptureFromCamera": self = .imageCaptureFromCamera
            case "ImagePickFromFile": self = .imagePickFromFile
            default: self = .unknown
            }
            return
        }

        let container = try decoder.container(keyedBy: CommandKey.self)
        if container.contains(.qrDisplay) {
            let data = try container.decode(QrDisplayData.self, forKey: .qrDisplay)
            self = .qrDisplay(data: data.data)
        } else if container.contains(.bleStartScanning) {
            let data = try container.decode(BleServiceData.self, forKey: .bleStartScanning)
            self = .bleStartScanning(serviceUuid: data.serviceUuid)
        } else if container.contains(.bleConnect) {
            let data = try container.decode(BleConnectData.self, forKey: .bleConnect)
            self = .bleConnect(deviceId: data.deviceId)
        } else if container.contains(.bleStartAdvertising) {
            let data = try container.decode(BleAdvertisingData.self, forKey: .bleStartAdvertising)
            self = .bleStartAdvertising(serviceUuid: data.serviceUuid, payload: data.payload)
        } else if container.contains(.bleWriteCharacteristic) {
            let data = try container.decode(BleCharacteristicData.self, forKey: .bleWriteCharacteristic)
            self = .bleWriteCharacteristic(uuid: data.uuid, data: data.data)
        } else if container.contains(.bleReadCharacteristic) {
            let data = try container.decode(BleReadData.self, forKey: .bleReadCharacteristic)
            self = .bleReadCharacteristic(uuid: data.uuid)
        } else if container.contains(.nfcActivate) {
            let data = try container.decode(NfcActivateData.self, forKey: .nfcActivate)
            self = .nfcActivate(payload: data.payload)
        } else if container.contains(.audioEmitChallenge) {
            let data = try container.decode(AudioChallengeData.self, forKey: .audioEmitChallenge)
            self = .audioEmitChallenge(data: data.data)
        } else if container.contains(.audioListenForResponse) {
            let data = try container.decode(AudioListenData.self, forKey: .audioListenForResponse)
            self = .audioListenForResponse(timeoutMs: data.timeoutMs)
        } else {
            self = .unknown
        }
    }

    private enum CommandKey: String, CodingKey {
        case qrDisplay = "QrDisplay"
        case bleStartAdvertising = "BleStartAdvertising"
        case bleStartScanning = "BleStartScanning"
        case bleConnect = "BleConnect"
        case bleWriteCharacteristic = "BleWriteCharacteristic"
        case bleReadCharacteristic = "BleReadCharacteristic"
        case nfcActivate = "NfcActivate"
        case audioEmitChallenge = "AudioEmitChallenge"
        case audioListenForResponse = "AudioListenForResponse"
    }

    private struct QrDisplayData: Decodable { let data: String }
    private struct BleServiceData: Decodable { let serviceUuid: String }
    private struct BleConnectData: Decodable { let deviceId: String }
    private struct BleAdvertisingData: Decodable { let serviceUuid: String; let payload: [UInt8] }
    private struct BleCharacteristicData: Decodable { let uuid: String; let data: [UInt8] }
    private struct BleReadData: Decodable { let uuid: String }
    private struct NfcActivateData: Decodable { let payload: [UInt8] }
    private struct AudioChallengeData: Decodable { let data: [UInt8] }
    private struct AudioListenData: Decodable { let timeoutMs: UInt64 }
}
