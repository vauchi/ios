// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
@testable import Vauchi
import XCTest

final class ModelsTests: XCTestCase {
    // MARK: - ScreenModel Decoding

    func testScreenModelDecodesFullJSON() throws {
        let json = Data("""
        {
            "screen_id": "welcome",
            "title": "Welcome",
            "subtitle": "Get started",
            "components": [
                {"Text": {"id": "t1", "content": "Hello", "style": "Body"}}
            ],
            "actions": [
                {"id": "next", "label": "Next", "style": "Primary", "enabled": true}
            ],
            "progress": {
                "current_step": 1,
                "total_steps": 5,
                "label": "Step 1 of 5"
            }
        }
        """.utf8)

        let screen = try coreJSONDecoder.decode(ScreenModel.self, from: json)

        XCTAssertEqual(screen.screenId, "welcome")
        XCTAssertEqual(screen.title, "Welcome")
        XCTAssertEqual(screen.subtitle, "Get started")
        XCTAssertEqual(screen.components.count, 1)
        XCTAssertEqual(screen.actions.count, 1)
        XCTAssertEqual(screen.actions[0].id, "next")
        XCTAssertEqual(screen.actions[0].label, "Next")
        XCTAssertEqual(screen.actions[0].style, .primary)
        XCTAssertEqual(screen.actions[0].enabled, true)
        XCTAssertEqual(screen.progress?.currentStep, 1)
        XCTAssertEqual(screen.progress?.totalSteps, 5)
        XCTAssertEqual(screen.progress?.label, "Step 1 of 5")
    }

    func testScreenModelDecodesWithoutOptionalFields() throws {
        let json = Data("""
        {
            "screen_id": "done",
            "title": "Done",
            "components": [],
            "actions": []
        }
        """.utf8)

        let screen = try coreJSONDecoder.decode(ScreenModel.self, from: json)

        XCTAssertEqual(screen.screenId, "done")
        XCTAssertEqual(screen.title, "Done")
        XCTAssertNil(screen.subtitle)
        XCTAssertEqual(screen.components.count, 0)
        XCTAssertEqual(screen.actions.count, 0)
        XCTAssertNil(screen.progress)
    }

    // MARK: - Component Variants

    func testComponentTextDecoding() throws {
        let json = Data("""
        {"Text": {"id": "t1", "content": "Hello world", "style": "Title"}}
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .text(text) = component else {
            XCTFail("Expected .text variant, got \(component)")
            return
        }
        XCTAssertEqual(text.id, "t1")
        XCTAssertEqual(text.content, "Hello world")
        XCTAssertEqual(text.style, .title)
    }

    func testComponentTextInputDecoding() throws {
        let json = Data("""
        {
            "TextInput": {
                "id": "name_input",
                "label": "Name",
                "value": "Alice",
                "placeholder": "Enter name",
                "max_length": 50,
                "validation_error": null,
                "input_type": "Text"
            }
        }
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .textInput(input) = component else {
            XCTFail("Expected .textInput variant, got \(component)")
            return
        }
        XCTAssertEqual(input.id, "name_input")
        XCTAssertEqual(input.label, "Name")
        XCTAssertEqual(input.value, "Alice")
        XCTAssertEqual(input.placeholder, "Enter name")
        XCTAssertEqual(input.maxLength, 50)
        XCTAssertNil(input.validationError)
        XCTAssertEqual(input.inputType, .text)
    }

    func testComponentToggleListDecoding() throws {
        let json = Data("""
        {
            "ToggleList": {
                "id": "groups",
                "label": "Select groups",
                "items": [
                    {"id": "family", "label": "Family", "selected": true, "subtitle": "Close family"},
                    {"id": "friends", "label": "Friends", "selected": false, "subtitle": null}
                ]
            }
        }
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .toggleList(list) = component else {
            XCTFail("Expected .toggleList variant, got \(component)")
            return
        }
        XCTAssertEqual(list.id, "groups")
        XCTAssertEqual(list.label, "Select groups")
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].id, "family")
        XCTAssertEqual(list.items[0].label, "Family")
        XCTAssertEqual(list.items[0].selected, true)
        XCTAssertEqual(list.items[0].subtitle, "Close family")
        XCTAssertEqual(list.items[1].id, "friends")
        XCTAssertEqual(list.items[1].selected, false)
        XCTAssertNil(list.items[1].subtitle)
    }

    func testComponentFieldListDecoding() throws {
        let json = Data("""
        {
            "FieldList": {
                "id": "fields",
                "fields": [
                    {
                        "id": "f1",
                        "field_type": "phone",
                        "label": "Phone",
                        "value": "+1234567890",
                        "visibility": "Shown"
                    }
                ],
                "visibility_mode": "ShowHide",
                "available_groups": ["Family", "Friends"]
            }
        }
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .fieldList(list) = component else {
            XCTFail("Expected .fieldList variant, got \(component)")
            return
        }
        XCTAssertEqual(list.id, "fields")
        XCTAssertEqual(list.fields.count, 1)
        XCTAssertEqual(list.fields[0].id, "f1")
        XCTAssertEqual(list.fields[0].fieldType, "phone")
        XCTAssertEqual(list.fields[0].label, "Phone")
        XCTAssertEqual(list.fields[0].value, "+1234567890")
        XCTAssertEqual(list.visibilityMode, .showHide)
        XCTAssertEqual(list.availableGroups, ["Family", "Friends"])
    }

    func testComponentCardPreviewDecoding() throws {
        let json = Data("""
        {
            "CardPreview": {
                "name": "Alice",
                "fields": [
                    {
                        "id": "f1",
                        "field_type": "email",
                        "label": "Email",
                        "value": "alice@example.com",
                        "visibility": "Shown"
                    }
                ],
                "group_views": [
                    {
                        "group_name": "Family",
                        "display_name": "Alice (Family)",
                        "visible_fields": []
                    }
                ],
                "selected_group": "Family"
            }
        }
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .cardPreview(preview) = component else {
            XCTFail("Expected .cardPreview variant, got \(component)")
            return
        }
        XCTAssertEqual(preview.name, "Alice")
        XCTAssertEqual(preview.fields.count, 1)
        XCTAssertEqual(preview.fields[0].value, "alice@example.com")
        XCTAssertEqual(preview.groupViews.count, 1)
        XCTAssertEqual(preview.groupViews[0].groupName, "Family")
        XCTAssertEqual(preview.groupViews[0].displayName, "Alice (Family)")
        XCTAssertEqual(preview.groupViews[0].visibleFields.count, 0)
        XCTAssertEqual(preview.selectedGroup, "Family")
    }

    func testComponentInfoPanelDecoding() throws {
        let json = Data("""
        {
            "InfoPanel": {
                "id": "security_info",
                "icon": "lock.shield",
                "title": "Security",
                "items": [
                    {"icon": "checkmark", "title": "E2E Encrypted", "detail": "Your data is safe"}
                ]
            }
        }
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .infoPanel(panel) = component else {
            XCTFail("Expected .infoPanel variant, got \(component)")
            return
        }
        XCTAssertEqual(panel.id, "security_info")
        XCTAssertEqual(panel.icon, "lock.shield")
        XCTAssertEqual(panel.title, "Security")
        XCTAssertEqual(panel.items.count, 1)
        XCTAssertEqual(panel.items[0].icon, "checkmark")
        XCTAssertEqual(panel.items[0].title, "E2E Encrypted")
        XCTAssertEqual(panel.items[0].detail, "Your data is safe")
    }

    func testComponentBannerDecoding() throws {
        let json = Data("""
        {"Banner": {"text": "Viewing as Bob", "action_label": "Exit", "action_id": "exit-preview"}}
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case let .banner(banner) = component else {
            XCTFail("Expected .banner variant, got \(component)")
            return
        }
        XCTAssertEqual(banner.text, "Viewing as Bob")
        XCTAssertEqual(banner.actionLabel, "Exit")
        XCTAssertEqual(banner.actionId, "exit-preview")
    }

    func testComponentDividerDecoding() throws {
        let json = Data("""
        "Divider"
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)

        guard case .divider = component else {
            XCTFail("Expected .divider variant, got \(component)")
            return
        }
    }

    // MARK: - UiFieldVisibility

    func testUiFieldVisibilityShown() throws {
        let json = Data("""
        "Shown"
        """.utf8)

        let visibility = try coreJSONDecoder.decode(UiFieldVisibility.self, from: json)

        guard case .shown = visibility else {
            XCTFail("Expected .shown, got \(visibility)")
            return
        }
    }

    func testUiFieldVisibilityHidden() throws {
        let json = Data("""
        "Hidden"
        """.utf8)

        let visibility = try coreJSONDecoder.decode(UiFieldVisibility.self, from: json)

        guard case .hidden = visibility else {
            XCTFail("Expected .hidden, got \(visibility)")
            return
        }
    }

    func testUiFieldVisibilityGroups() throws {
        let json = Data("""
        {"Groups": ["Family", "Friends"]}
        """.utf8)

        let visibility = try coreJSONDecoder.decode(UiFieldVisibility.self, from: json)

        guard case let .groups(groups) = visibility else {
            XCTFail("Expected .groups variant, got \(visibility)")
            return
        }
        XCTAssertEqual(groups, ["Family", "Friends"])
    }

    func testUiFieldVisibilityGroupsSingleGroup() throws {
        let json = Data("""
        {"Groups": ["Family"]}
        """.utf8)

        let visibility = try coreJSONDecoder.decode(UiFieldVisibility.self, from: json)

        guard case let .groups(groups) = visibility else {
            XCTFail("Expected .groups variant, got \(visibility)")
            return
        }
        XCTAssertEqual(groups, ["Family"])
    }

    // MARK: - ActionResult

    func testActionResultUpdateScreen() throws {
        let json = Data("""
        {
            "UpdateScreen": {
                "screen_id": "step2",
                "title": "Step 2",
                "components": [],
                "actions": []
            }
        }
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .updateScreen(screen) = result else {
            XCTFail("Expected .updateScreen, got \(result)")
            return
        }
        XCTAssertEqual(screen.screenId, "step2")
        XCTAssertEqual(screen.title, "Step 2")
    }

    func testActionResultNavigateTo() throws {
        let json = Data("""
        {
            "NavigateTo": {
                "screen_id": "groups",
                "title": "Groups",
                "components": [],
                "actions": []
            }
        }
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .navigateTo(screen) = result else {
            XCTFail("Expected .navigateTo, got \(result)")
            return
        }
        XCTAssertEqual(screen.screenId, "groups")
        XCTAssertEqual(screen.title, "Groups")
    }

    func testActionResultValidationError() throws {
        let json = Data("""
        {
            "ValidationError": {
                "component_id": "name_input",
                "message": "Name is required"
            }
        }
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .validationError(componentId, message) = result else {
            XCTFail("Expected .validationError, got \(result)")
            return
        }
        XCTAssertEqual(componentId, "name_input")
        XCTAssertEqual(message, "Name is required")
    }

    func testActionResultComplete() throws {
        let json = Data("""
        "Complete"
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case .complete = result else {
            XCTFail("Expected .complete, got \(result)")
            return
        }
    }

    func testActionResultExchangeCommands() throws {
        let json = Data("""
        {"ExchangeCommands": {"commands": ["QrRequestScan", {"QrDisplay": {"data": "test-qr"}}]}}
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .exchangeCommands(commands) = result else {
            XCTFail("Expected .exchangeCommands, got \(result)")
            return
        }
        XCTAssertEqual(commands.count, 2)
        guard case .qrRequestScan = commands[0] else {
            XCTFail("Expected .qrRequestScan, got \(commands[0])")
            return
        }
        guard case let .qrDisplay(data) = commands[1] else {
            XCTFail("Expected .qrDisplay, got \(commands[1])")
            return
        }
        XCTAssertEqual(data, "test-qr")
    }

    func testActionResultShowToast() throws {
        let json = Data("""
        {"ShowToast": {"message": "Saved", "undo_action_id": "undo_1"}}
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .showToast(message, undoActionId) = result else {
            XCTFail("Expected .showToast, got \(result)")
            return
        }
        XCTAssertEqual(message, "Saved")
        XCTAssertEqual(undoActionId, "undo_1")
    }

    func testActionResultEditContact() throws {
        let json = Data("""
        {"EditContact": {"contact_id": "c123"}}
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .editContact(contactId) = result else {
            XCTFail("Expected .editContact, got \(result)")
            return
        }
        XCTAssertEqual(contactId, "c123")
    }

    func testActionResultOpenEntryDetail() throws {
        let json = Data("""
        {"OpenEntryDetail": {"field_id": "phone_1"}}
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)

        guard case let .openEntryDetail(fieldId) = result else {
            XCTFail("Expected .openEntryDetail, got \(result)")
            return
        }
        XCTAssertEqual(fieldId, "phone_1")
    }

    // MARK: - UserAction Encoding

    func testUserActionTextChangedEncoding() throws {
        let action = UserAction.textChanged(componentId: "name_input", value: "Bob")

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["TextChanged"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'TextChanged' key at top level")
        XCTAssertEqual(inner?["component_id"] as? String, "name_input")
        XCTAssertEqual(inner?["value"] as? String, "Bob")
    }

    func testUserActionActionPressedEncoding() throws {
        let action = UserAction.actionPressed(actionId: "next")

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["ActionPressed"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'ActionPressed' key at top level")
        XCTAssertEqual(inner?["action_id"] as? String, "next")
    }

    func testUserActionItemToggledEncoding() throws {
        let action = UserAction.itemToggled(componentId: "groups", itemId: "family")

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["ItemToggled"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'ItemToggled' key at top level")
        XCTAssertEqual(inner?["component_id"] as? String, "groups")
        XCTAssertEqual(inner?["item_id"] as? String, "family")
    }

    func testUserActionFieldVisibilityChangedEncoding() throws {
        let action = UserAction.fieldVisibilityChanged(
            fieldId: "f1", groupId: "Family", visible: true
        )

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["FieldVisibilityChanged"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'FieldVisibilityChanged' key at top level")
        XCTAssertEqual(inner?["field_id"] as? String, "f1")
        XCTAssertEqual(inner?["group_id"] as? String, "Family")
        XCTAssertEqual(inner?["visible"] as? Bool, true)
    }

    func testUserActionFieldVisibilityChangedNilGroupEncoding() throws {
        let action = UserAction.fieldVisibilityChanged(
            fieldId: "f1", groupId: nil, visible: false
        )

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["FieldVisibilityChanged"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'FieldVisibilityChanged' key at top level")
        XCTAssertEqual(inner?["field_id"] as? String, "f1")
        // group_id should be absent (encodeIfPresent with nil)
        XCTAssertNil(inner?["group_id"])
        XCTAssertEqual(inner?["visible"] as? Bool, false)
    }

    func testUserActionGroupViewSelectedEncoding() throws {
        let action = UserAction.groupViewSelected(groupName: "Family")

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["GroupViewSelected"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'GroupViewSelected' key at top level")
        XCTAssertEqual(inner?["group_name"] as? String, "Family")
    }

    func testUserActionGroupViewSelectedNilEncoding() throws {
        let action = UserAction.groupViewSelected(groupName: nil)

        let data = try coreJSONEncoder.encode(action)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let inner = jsonObject?["GroupViewSelected"] as? [String: Any]
        XCTAssertNotNil(inner, "Expected 'GroupViewSelected' key at top level")
        XCTAssertNil(inner?["group_name"])
    }

    // MARK: - Unknown Variant Handling

    func testUnknownComponentVariantDecodesAsUnknown() throws {
        let json = Data("""
        {"UnknownWidget": {"id": "x"}}
        """.utf8)

        let component = try coreJSONDecoder.decode(Component.self, from: json)
        guard case .unknown = component else {
            XCTFail("Expected .unknown, got \(component)")
            return
        }
    }

    func testUnknownActionResultVariantDecodesAsUnknown() throws {
        let json = Data("""
        {"UnknownResult": {}}
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)
        guard case .unknown = result else {
            XCTFail("Expected .unknown, got \(result)")
            return
        }
    }

    func testUnknownUnitActionResultVariantDecodesAsUnknown() throws {
        let json = Data("""
        "FutureUnitVariant"
        """.utf8)

        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)
        guard case .unknown = result else {
            XCTFail("Expected .unknown for unknown unit variant, got \(result)")
            return
        }
    }

    func testUnknownUiFieldVisibilityVariantThrows() {
        let json = Data("""
        "Unknown"
        """.utf8)

        XCTAssertThrowsError(
            try coreJSONDecoder.decode(UiFieldVisibility.self, from: json)
        ) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(
                context.debugDescription.contains("Unknown UiFieldVisibility variant"),
                "Expected 'Unknown UiFieldVisibility variant' in error, got: \(context.debugDescription)"
            )
        }
    }

    // MARK: - Dropdown Component Decoding

    func testDropdownComponentDecodes() throws {
        let json = Data("""
        {"Dropdown": {"id": "theme", "label": "Theme", "selected": "dark", "options": [{"id": "dark", "label": "Dark"}, {"id": "light", "label": "Light"}]}}
        """.utf8)
        let component = try coreJSONDecoder.decode(Component.self, from: json)
        if case let .dropdown(dropdown) = component {
            XCTAssertEqual(dropdown.id, "theme")
            XCTAssertEqual(dropdown.label, "Theme")
            XCTAssertEqual(dropdown.selected, "dark")
            XCTAssertEqual(dropdown.options.count, 2)
            XCTAssertEqual(dropdown.options[0].id, "dark")
            XCTAssertEqual(dropdown.options[0].label, "Dark")
        } else {
            XCTFail("Expected .dropdown, got \(component)")
        }
    }

    func testDropdownComponentDecodesNullSelected() throws {
        let json = Data("""
        {"Dropdown": {"id": "lang", "label": "Language", "selected": null, "options": [{"id": "en", "label": "English"}]}}
        """.utf8)
        let component = try coreJSONDecoder.decode(Component.self, from: json)
        if case let .dropdown(dropdown) = component {
            XCTAssertNil(dropdown.selected)
            XCTAssertEqual(dropdown.options.count, 1)
        } else {
            XCTFail("Expected .dropdown")
        }
    }

    // MARK: - ShowFormDialog / PreviewAs Decoding

    func testShowFormDialogDecodes() throws {
        let json = Data("""
        {"ShowFormDialog": {"dialog_type": "create_group", "context_id": "grp-1"}}
        """.utf8)
        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)
        if case let .showFormDialog(dialogType, contextId) = result {
            XCTAssertEqual(dialogType, "create_group")
            XCTAssertEqual(contextId, "grp-1")
        } else {
            XCTFail("Expected .showFormDialog, got \(result)")
        }
    }

    func testShowFormDialogDecodesNullContextId() throws {
        let json = Data("""
        {"ShowFormDialog": {"dialog_type": "create_group", "context_id": null}}
        """.utf8)
        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)
        if case let .showFormDialog(_, contextId) = result {
            XCTAssertNil(contextId)
        } else {
            XCTFail("Expected .showFormDialog")
        }
    }

    func testPreviewAsDecodes() throws {
        let json = Data("""
        {"PreviewAs": {"contact_id": "c42"}}
        """.utf8)
        let result = try coreJSONDecoder.decode(ActionResult.self, from: json)
        if case let .previewAs(contactId) = result {
            XCTAssertEqual(contactId, "c42")
        } else {
            XCTFail("Expected .previewAs, got \(result)")
        }
    }

    // MARK: - ContactItem + ListItemAction wire format (core!637)

    func testContactItemDecodesWithActions() throws {
        let json = Data("""
        {
            "id": "c1",
            "name": "Alice",
            "subtitle": "alice@example.org",
            "avatar_initials": "A",
            "status": null,
            "searchable_fields": ["alice@example.org", "+41 79 123 45 67"],
            "actions": [
                {"id": "archive", "label": "Archive", "kind": "archive", "destructive": false},
                {"id": "delete", "label": "Delete", "kind": "delete", "destructive": true}
            ]
        }
        """.utf8)
        let contact = try coreJSONDecoder.decode(ContactItem.self, from: json)
        XCTAssertEqual(contact.id, "c1")
        XCTAssertEqual(contact.name, "Alice")
        XCTAssertEqual(contact.avatarInitials, "A")
        XCTAssertEqual(contact.searchableFields, ["alice@example.org", "+41 79 123 45 67"])
        XCTAssertEqual(contact.actions.count, 2)
        XCTAssertEqual(contact.actions[0].id, "archive")
        XCTAssertEqual(contact.actions[0].kind, .archive)
        XCTAssertFalse(contact.actions[0].destructive)
        XCTAssertEqual(contact.actions[1].kind, .delete)
        XCTAssertTrue(contact.actions[1].destructive)
    }

    func testContactItemLegacyFixtureWithoutNewFields() throws {
        // Fixtures written before core!637 omit `actions` + `searchable_fields`.
        // Decoding must still succeed — the ContactItem init provides [] defaults.
        let json = Data("""
        {"id": "c1", "name": "Bob", "avatar_initials": "B"}
        """.utf8)
        let contact = try coreJSONDecoder.decode(ContactItem.self, from: json)
        XCTAssertEqual(contact.id, "c1")
        XCTAssertTrue(contact.actions.isEmpty)
        XCTAssertTrue(contact.searchableFields.isEmpty)
    }

    func testListItemActionKindForwardCompatFallsBackToUnknown() throws {
        // A newer core ships an unrecognised kind. Decoding must not throw —
        // we degrade to `.unknown` so the UI can render a generic affordance.
        let json = Data("""
        {"id": "x", "label": "Future", "kind": "promote_to_vip", "destructive": false}
        """.utf8)
        let action = try coreJSONDecoder.decode(ListItemAction.self, from: json)
        XCTAssertEqual(action.kind, .unknown)
    }

    func testUserActionListItemActionEncodesSerdeWireFormat() throws {
        let action: UserAction = .listItemAction(
            componentId: "contacts",
            itemId: "c1",
            actionId: "archive"
        )
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let payload = decoded?["ListItemAction"] as? [String: Any]
        XCTAssertNotNil(payload, "expected outer serde variant key ListItemAction")
        XCTAssertEqual(payload?["component_id"] as? String, "contacts")
        XCTAssertEqual(payload?["item_id"] as? String, "c1")
        XCTAssertEqual(payload?["action_id"] as? String, "archive")
    }
}
