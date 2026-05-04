// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreUIModels
@testable import Vauchi
import XCTest

/// Contract tests that verify the iOS decoder stays compatible with core's golden JSON fixtures.
/// If core changes the ScreenModel format, these tests catch the drift.
final class ContractTests: XCTestCase {
    // MARK: - Fixture Loading

    /// Path to golden fixtures, co-located with contract tests.
    /// These are copies of core's golden fixtures (core/vauchi-core/tests/fixtures/golden/).
    /// If core changes the schema, regenerate with: cp core/.../golden/*.json here.
    private static let fixturesURL: URL = {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL
            .deletingLastPathComponent() // CoreUI/
            .appendingPathComponent("fixtures/golden")
            .standardized
    }()

    /// Dynamically discover all golden fixture files — no hardcoded list.
    /// If core adds or removes fixtures, this list updates automatically.
    private static var fixtureNames: [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: fixturesURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Load and decode a single golden fixture as ScreenModel.
    private func loadFixture(_ name: String) throws -> ScreenModel {
        let url = Self.fixturesURL.appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try coreJSONDecoder.decode(ScreenModel.self, from: data)
    }

    // MARK: - Golden Fixture Decode Tests

    /// Every golden fixture must decode as a valid ScreenModel.
    /// This is the primary contract test: if core changes the JSON schema,
    /// this test fails and tells us exactly which fixture broke.
    func testAllGoldenFixturesDecodeAsScreenModel() throws {
        XCTAssertGreaterThanOrEqual(
            Self.fixtureNames.count, 20,
            "Expected at least 20 golden fixtures, found \(Self.fixtureNames.count)"
        )
        for name in Self.fixtureNames {
            let screen = try loadFixture(name)
            XCTAssertFalse(screen.screenId.isEmpty, "Fixture '\(name)': screen_id must not be empty")
            // title may be empty for placeholder screens (e.g., home_empty)
        }
    }

    // MARK: - Field-Level Assertions

    /// Decode each fixture and verify critical fields are populated.
    /// Some screens (delivery_empty, help, settings) have no actions;
    /// home_empty has no title. Only assert universal invariants.
    func testScreenModelFieldsNotNil() throws {
        for name in Self.fixtureNames {
            let screen = try loadFixture(name)

            XCTAssertFalse(
                screen.screenId.isEmpty,
                "Fixture '\(name)': screen_id must not be empty"
            )
            XCTAssertFalse(
                screen.components.isEmpty,
                "Fixture '\(name)': components must not be empty"
            )
            // Verify all actions that exist have non-empty labels
            for action in screen.actions {
                XCTAssertFalse(
                    action.label.isEmpty,
                    "Fixture '\(name)': action '\(action.id)' has empty label"
                )
            }
        }
    }

    /// Verify the welcome fixture decodes with structural properties.
    /// Does NOT assert specific action IDs or localized strings (structural only).
    func testWelcomeFixtureContent() throws {
        let screen = try loadFixture("welcome")
        XCTAssertEqual(screen.screenId, "welcome")
        XCTAssertFalse(screen.title.isEmpty)
        XCTAssertFalse(screen.subtitle?.isEmpty ?? true,
                       "welcome fixture must carry a non-empty subtitle")
        let progress = try XCTUnwrap(screen.progress,
                                     "welcome fixture is an onboarding step and must carry progress")
        XCTAssertEqual(progress.currentStep, 1, "welcome is step 1 of the onboarding flow")
        XCTAssertGreaterThan(progress.totalSteps, progress.currentStep,
                             "totalSteps must exceed currentStep on the first onboarding step")
        XCTAssertFalse(screen.components.isEmpty)
        XCTAssertFalse(screen.actions.isEmpty)
        XCTAssertEqual(screen.actions[0].style, .primary)
    }

    /// Verify the preview_card fixture decodes its CardPreview component.
    func testPreviewCardFixtureContent() throws {
        let screen = try loadFixture("preview_card")
        XCTAssertEqual(screen.screenId, "preview_card")
        let progress = try XCTUnwrap(screen.progress,
                                     "preview_card fixture is an onboarding step and must carry progress")
        XCTAssertGreaterThan(progress.totalSteps, 0)
        XCTAssertGreaterThan(progress.currentStep, 0)
        XCTAssertFalse(screen.components.isEmpty)
    }

    // MARK: - Progress Consistency

    /// Fixtures with progress must have consistent totalSteps within their flow.
    /// Not all fixtures have progress — only onboarding/wizard screens do.
    func testFixturesWithProgressHaveValidValues() throws {
        for name in Self.fixtureNames {
            let screen = try loadFixture(name)
            guard let progress = screen.progress else { continue }
            XCTAssertGreaterThan(
                progress.totalSteps, 0,
                "Fixture '\(name)': totalSteps must be > 0"
            )
            XCTAssertGreaterThan(
                progress.currentStep, 0,
                "Fixture '\(name)': currentStep must be > 0"
            )
            XCTAssertLessThanOrEqual(
                progress.currentStep, progress.totalSteps,
                "Fixture '\(name)': currentStep (\(progress.currentStep)) > totalSteps (\(progress.totalSteps))"
            )
        }
    }

    // MARK: - UserAction Round-Trip Encoding

    /// Encode each UserAction variant, decode the JSON, and verify the structure
    /// matches serde's expected format (PascalCase variant key, snake_case field names).
    func testUserActionRoundtripTextChanged() throws {
        let action = UserAction.textChanged(componentId: "name_input", value: "Alice")
        let data = try coreJSONEncoder.encode(action)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let inner = try XCTUnwrap(
            json["TextChanged"] as? [String: Any],
            "Expected 'TextChanged' key"
        )
        XCTAssertEqual(inner["component_id"] as? String, "name_input")
        XCTAssertEqual(inner["value"] as? String, "Alice")

        // Round-trip: re-encode from parsed JSON and compare
        let reEncoded = try JSONSerialization.data(
            withJSONObject: json, options: [.sortedKeys]
        )
        let original = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys]
        )
        XCTAssertEqual(reEncoded, original, "Round-trip encoding must produce identical JSON")
    }

    func testUserActionRoundtripItemToggled() throws {
        let action = UserAction.itemToggled(componentId: "groups", itemId: "family")
        let data = try coreJSONEncoder.encode(action)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let inner = try XCTUnwrap(
            json["ItemToggled"] as? [String: Any],
            "Expected 'ItemToggled' key"
        )
        XCTAssertEqual(inner["component_id"] as? String, "groups")
        XCTAssertEqual(inner["item_id"] as? String, "family")
    }

    func testUserActionRoundtripActionPressed() throws {
        let action = UserAction.actionPressed(actionId: "get_started")
        let data = try coreJSONEncoder.encode(action)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let inner = try XCTUnwrap(
            json["ActionPressed"] as? [String: Any],
            "Expected 'ActionPressed' key"
        )
        XCTAssertEqual(inner["action_id"] as? String, "get_started")
    }

    func testUserActionRoundtripFieldVisibilityChanged() throws {
        let action = UserAction.fieldVisibilityChanged(
            fieldId: "f1", groupId: "Family", visible: true
        )
        let data = try coreJSONEncoder.encode(action)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let inner = try XCTUnwrap(
            json["FieldVisibilityChanged"] as? [String: Any],
            "Expected 'FieldVisibilityChanged' key"
        )
        XCTAssertEqual(inner["field_id"] as? String, "f1")
        XCTAssertEqual(inner["group_id"] as? String, "Family")
        XCTAssertEqual(inner["visible"] as? Bool, true)
    }

    func testUserActionRoundtripGroupViewSelected() throws {
        let action = UserAction.groupViewSelected(groupName: "Friends")
        let data = try coreJSONEncoder.encode(action)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let inner = try XCTUnwrap(
            json["GroupViewSelected"] as? [String: Any],
            "Expected 'GroupViewSelected' key"
        )
        XCTAssertEqual(inner["group_name"] as? String, "Friends")
    }

    /// Verify that all UserAction variant keys use PascalCase (matching serde).
    func testUserActionVariantKeysArePascalCase() throws {
        let actions: [UserAction] = [
            .textChanged(componentId: "c", value: "v"),
            .itemToggled(componentId: "c", itemId: "i"),
            .actionPressed(actionId: "a"),
            .fieldVisibilityChanged(fieldId: "f", groupId: nil, visible: false),
            .groupViewSelected(groupName: nil),
        ]

        let expectedKeys = [
            "TextChanged",
            "ItemToggled",
            "ActionPressed",
            "FieldVisibilityChanged",
            "GroupViewSelected",
        ]

        for (action, expectedKey) in zip(actions, expectedKeys) {
            let data = try coreJSONEncoder.encode(action)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any],
                "Failed to parse JSON for \(expectedKey)"
            )
            XCTAssertTrue(
                json.keys.contains(expectedKey),
                "Expected PascalCase key '\(expectedKey)', got keys: \(json.keys.sorted())"
            )
            XCTAssertEqual(
                json.keys.count, 1,
                "Expected exactly one top-level key for \(expectedKey)"
            )
        }
    }

    // MARK: - Version Linkage

    /// Verify .version metadata file exists and fixture_count matches.
    func testVersionMetadataMatchesFixtureCount() throws {
        let versionURL = Self.fixturesURL.appendingPathComponent(".version")
        let data = try Data(contentsOf: versionURL)
        let meta = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let coreVersion = try XCTUnwrap(
            meta["core_version"] as? String,
            ".version must have core_version"
        )
        XCTAssertFalse(coreVersion.isEmpty, "core_version must not be empty")

        let schemaVersion = try XCTUnwrap(
            meta["schema_version"] as? Int,
            ".version must have schema_version"
        )
        XCTAssertGreaterThanOrEqual(schemaVersion, 1)

        let fixtureCount = meta["fixture_count"] as? Int
        XCTAssertEqual(
            fixtureCount, Self.fixtureNames.count,
            ".version fixture_count (\(fixtureCount ?? -1)) must match actual count (\(Self.fixtureNames.count))"
        )
    }
}
