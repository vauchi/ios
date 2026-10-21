// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Pins the JSON `buildRenderContextJson` sends to core's
// `setRenderContextJson`. On "Follow system" no `locale` is sent, so core
// rendered English until the OS language travelled as `system_locale`
// (vauchi/private#721).

@testable import Vauchi
import XCTest

final class RenderContextPusherTests: XCTestCase {
    private func parse(_ json: String) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [String: String])
    }

    func testFollowingTheSystemSendsTheSystemLanguageAndNoPickedLanguage() throws {
        let json = try parse(buildRenderContextJson(themeId: nil, locale: nil, systemLocale: "fr-CH"))

        XCTAssertEqual(json, ["system_locale": "fr-CH"])
    }

    func testAPickedLanguageStillTravelsWithTheSystemLanguage() throws {
        let json = try parse(buildRenderContextJson(themeId: "cyber", locale: "de", systemLocale: "fr-CH"))

        XCTAssertEqual(json, ["theme_id": "cyber", "locale": "de", "system_locale": "fr-CH"])
    }

    func testAnUnknownSystemLanguageIsLeftOut() throws {
        let json = try parse(buildRenderContextJson(themeId: nil, locale: "de", systemLocale: nil))

        XCTAssertEqual(json, ["locale": "de"])
    }

    func testAQuoteOrBackslashInTheSystemTagStaysInsideItsString() throws {
        let json = try parse(buildRenderContextJson(themeId: nil, locale: nil, systemLocale: "x\"\\y"))

        XCTAssertEqual(json, ["system_locale": "x\"\\y"])
    }
}
