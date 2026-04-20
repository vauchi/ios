// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

final class PasscodePolicyTests: XCTestCase {
    // MARK: - Policy bounds

    func testMinLengthIsFour() {
        XCTAssertEqual(PasscodePolicy.minLength, 4)
    }

    func testMaxLengthIsSixtyFour() {
        XCTAssertEqual(PasscodePolicy.maxLength, 64)
    }

    // MARK: - isValid

    func testIsValidRejectsShort() {
        XCTAssertFalse(PasscodePolicy.isValid(""))
        XCTAssertFalse(PasscodePolicy.isValid("1"))
        XCTAssertFalse(PasscodePolicy.isValid("12"))
        XCTAssertFalse(PasscodePolicy.isValid("123"))
    }

    func testIsValidAcceptsMinLength() {
        XCTAssertTrue(PasscodePolicy.isValid("1234"))
        XCTAssertTrue(PasscodePolicy.isValid("abcd"))
    }

    func testIsValidAcceptsTypicalSixDigitPin() {
        XCTAssertTrue(PasscodePolicy.isValid("123456"))
    }

    func testIsValidAcceptsLongPasswords() {
        XCTAssertTrue(PasscodePolicy.isValid("correct horse battery staple"))
    }

    func testIsValidAcceptsMaxLength() {
        let maxPassword = String(repeating: "a", count: 64)
        XCTAssertTrue(PasscodePolicy.isValid(maxPassword))
    }

    func testIsValidRejectsOverLong() {
        let tooLong = String(repeating: "a", count: 65)
        XCTAssertFalse(PasscodePolicy.isValid(tooLong))
    }

    // MARK: - Non-digit acceptance (regression for lockout bug)

    /// The app-password entry field used to filter non-digits and require
    /// exactly 6 characters, while the setup path accepted 4+ of any
    /// character. Users who set an alphanumeric password were permanently
    /// locked out. Entry and setup must accept the same character set.
    func testIsValidAcceptsAlphanumeric() {
        XCTAssertTrue(PasscodePolicy.isValid("letmein"))
        XCTAssertTrue(PasscodePolicy.isValid("P@ssw0rd!"))
    }

    // MARK: - clamp

    func testClampPassesShortInputThrough() {
        XCTAssertEqual(PasscodePolicy.clamp(""), "")
        XCTAssertEqual(PasscodePolicy.clamp("1234"), "1234")
        XCTAssertEqual(PasscodePolicy.clamp("password"), "password")
    }

    func testClampTruncatesToMaxLength() {
        let input = String(repeating: "x", count: 100)
        let clamped = PasscodePolicy.clamp(input)
        XCTAssertEqual(clamped.count, 64)
        XCTAssertEqual(clamped, String(repeating: "x", count: 64))
    }

    func testClampPreservesNonDigitCharacters() {
        XCTAssertEqual(PasscodePolicy.clamp("P@ssw0rd!"), "P@ssw0rd!")
    }
}
