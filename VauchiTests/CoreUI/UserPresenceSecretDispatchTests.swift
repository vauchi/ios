// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core asks for the operating system's user-presence check with
// `Command::CreateUserPresenceSecret { prompt }` (first time on this device)
// and `Command::RevealUserPresenceSecret { prompt }` (after that), and reads
// the answer as `Event::UserPresenceSecretCreated { secret }`,
// `UserPresenceSecretRevealed { secret }`, `UserPresenceCheckCancelled`, or
// `HardwareUnavailable { transport: "user_presence" }`
// (`core/vauchi-core/src/platform.rs`, ADR-066, vauchi/private#712).
//
// CC-23: the keychain item with `.userPresence` access control is the true
// boundary — no unit test can satisfy the OS check — so it is faked at the
// `SecItemAdd` / `SecItemCopyMatching` status level and these pin the
// decode, the dispatch, and the exact event JSON each outcome hands Core.
//
// Traces to: features/privacy_compliance.feature

import Security
@testable import Vauchi
import VauchiPlatform
import XCTest

/// Keychain stand-in: holds one item, and answers a read with `readStatus`
/// in place of the OS check when one is set.
final class FakeUserPresenceKeychain: UserPresenceKeychain {
    var stored: Data?
    var replaceStatus: OSStatus = errSecSuccess
    var readStatus: OSStatus?
    var readOverride: Data?
    private(set) var replaceCount = 0
    private(set) var readPrompts: [String] = []

    func replaceSecret(_ secret: Data) -> OSStatus {
        replaceCount += 1
        guard replaceStatus == errSecSuccess else { return replaceStatus }
        stored = secret
        return errSecSuccess
    }

    func readSecret(prompt: String) -> UserPresenceKeychainRead {
        readPrompts.append(prompt)
        if let readStatus {
            return UserPresenceKeychainRead(status: readStatus, secret: nil)
        }
        if let readOverride {
            return UserPresenceKeychainRead(status: errSecSuccess, secret: readOverride)
        }
        guard let stored else {
            return UserPresenceKeychainRead(status: errSecItemNotFound, secret: nil)
        }
        return UserPresenceKeychainRead(status: errSecSuccess, secret: stored)
    }
}

@MainActor
final class UserPresenceSecretDispatchTests: XCTestCase {
    private let prompt = "Confirm it is you"
    private let firstSecret = [UInt8](repeating: 7, count: 32)
    private let secondSecret = [UInt8]((0 ..< 32).map { UInt8($0) })

    private var keychain: FakeUserPresenceKeychain!
    private var randomQueue: [[UInt8]?] = []

    override func setUp() {
        super.setUp()
        keychain = FakeUserPresenceKeychain()
        randomQueue = [firstSecret, secondSecret]
    }

    private func makeService() -> UserPresenceSecretService {
        UserPresenceSecretService(
            keychain: keychain,
            randomBytes: { [unowned self] count in
                XCTAssertEqual(count, 32)
                return randomQueue.isEmpty ? nil : randomQueue.removeFirst()
            },
            perform: { $0() }
        )
    }

    private func create() -> UserPresenceOutcome? {
        var outcome: UserPresenceOutcome?
        makeService().create(prompt: prompt) { outcome = $0 }
        return outcome
    }

    private func reveal() -> UserPresenceOutcome? {
        var outcome: UserPresenceOutcome?
        makeService().reveal(prompt: prompt) { outcome = $0 }
        return outcome
    }

    // MARK: - Decode

    func testCreateUserPresenceSecretDecodesWithItsPrompt() throws {
        let commands = try decodeCommands(
            #"{"commands":[{"CreateUserPresenceSecret":{"prompt":"Confirm it is you"}}]}"#
        )

        guard case let .createUserPresenceSecret(prompt) = try XCTUnwrap(commands.first) else {
            return XCTFail("expected .createUserPresenceSecret, got \(commands)")
        }
        XCTAssertEqual(prompt, "Confirm it is you")
    }

    func testRevealUserPresenceSecretDecodesWithItsPrompt() throws {
        let commands = try decodeCommands(
            #"{"commands":[{"RevealUserPresenceSecret":{"prompt":"Confirm it is you"}}]}"#
        )

        guard case let .revealUserPresenceSecret(prompt) = try XCTUnwrap(commands.first) else {
            return XCTFail("expected .revealUserPresenceSecret, got \(commands)")
        }
        XCTAssertEqual(prompt, "Confirm it is you")
    }

    // MARK: - Dispatch

    func testCreateCommandSealsAndChecksWithCoresPrompt() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "User Presence Dispatch Test")
        let viewModel = AppViewModel(appEngine: repo.appEngine)
        viewModel.userPresenceSecretService = makeService()

        viewModel.receivePresentationEnvelope(
            #"{"commands":[{"CreateUserPresenceSecret":{"prompt":"Confirm it is you"}}]}"#
        )

        XCTAssertEqual(keychain.stored, Data(firstSecret))
        XCTAssertEqual(keychain.readPrompts, ["Confirm it is you"])
        XCTAssertNil(viewModel.alertMessage, "the command must not surface as a presentation error")
    }

    func testRevealCommandReadsWithCoresPromptAndSealsNothing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "User Presence Dispatch Test")
        let viewModel = AppViewModel(appEngine: repo.appEngine)
        keychain.stored = Data(secondSecret)
        viewModel.userPresenceSecretService = makeService()

        viewModel.receivePresentationEnvelope(
            #"{"commands":[{"RevealUserPresenceSecret":{"prompt":"Confirm it is you"}}]}"#
        )

        XCTAssertEqual(keychain.replaceCount, 0)
        XCTAssertEqual(keychain.readPrompts, ["Confirm it is you"])
        XCTAssertNil(viewModel.alertMessage)
    }

    // MARK: - Create

    func testCreateSealsThirtyTwoRandomBytesAndAnswersCreated() {
        XCTAssertEqual(create(), .created(secret: firstSecret))
        XCTAssertEqual(keychain.stored, Data(firstSecret))
        XCTAssertEqual(keychain.readPrompts, [prompt], "the OS check runs now, with Core's prompt")
    }

    func testCreatedEventIsCoresCanonicalJson() {
        XCTAssertEqual(
            UserPresenceOutcome.created(secret: [1, 2, 255]).eventJson,
            #"{"UserPresenceSecretCreated":{"secret":[1,2,255]}}"#
        )
    }

    func testASecondCreateReplacesTheItem() {
        _ = create()
        let second = create()

        XCTAssertEqual(second, .created(secret: secondSecret))
        XCTAssertEqual(keychain.replaceCount, 2)
        XCTAssertEqual(keychain.stored, Data(secondSecret))
        XCTAssertEqual(reveal(), .revealed(secret: secondSecret))
    }

    func testCreateCancelledAtTheCheckAnswersCancelled() {
        keychain.readStatus = errSecUserCanceled

        XCTAssertEqual(create(), .cancelled)
    }

    func testCreateWhoseItemCannotBeStoredAnswersUnavailableWithoutAPrompt() {
        keychain.replaceStatus = errSecNotAvailable

        XCTAssertEqual(create(), .unavailable)
        XCTAssertEqual(keychain.readPrompts, [], "no check for a secret that was never sealed")
    }

    func testCreateWithoutRandomBytesAnswersUnavailableAndStoresNothing() {
        randomQueue = [nil]

        XCTAssertEqual(create(), .unavailable)
        XCTAssertNil(keychain.stored)
        XCTAssertEqual(keychain.replaceCount, 0)
    }

    func testCreateWhoseReadBackDiffersAnswersUnavailable() {
        keychain.readOverride = Data(secondSecret)

        XCTAssertEqual(create(), .unavailable)
    }

    // MARK: - Reveal

    func testRevealAnswersTheStoredSecret() {
        keychain.stored = Data(secondSecret)

        XCTAssertEqual(reveal(), .revealed(secret: secondSecret))
        XCTAssertEqual(keychain.readPrompts, [prompt])
    }

    func testRevealedEventIsCoresCanonicalJson() {
        XCTAssertEqual(
            UserPresenceOutcome.revealed(secret: [0, 128]).eventJson,
            #"{"UserPresenceSecretRevealed":{"secret":[0,128]}}"#
        )
    }

    func testRevealCancelledAnswersCancelled() {
        keychain.stored = Data(firstSecret)
        keychain.readStatus = errSecUserCanceled

        XCTAssertEqual(reveal(), .cancelled)
    }

    func testRevealWhoseCheckFailedAnswersCancelled() {
        keychain.stored = Data(firstSecret)
        keychain.readStatus = errSecAuthFailed

        XCTAssertEqual(reveal(), .cancelled)
    }

    func testRevealWithoutAnItemAnswersUnavailable() {
        XCTAssertEqual(reveal(), .unavailable)
    }

    func testRevealOfAWrongSizedItemAnswersUnavailable() {
        keychain.stored = Data(repeating: 7, count: 31)

        XCTAssertEqual(reveal(), .unavailable)
    }

    func testRevealWhenTheKeychainIsLockedAnswersUnavailable() {
        keychain.stored = Data(firstSecret)
        keychain.readStatus = errSecInteractionNotAllowed

        XCTAssertEqual(reveal(), .unavailable)
    }

    // MARK: - Events without a secret

    func testCancelledEventIsCoresCanonicalJson() {
        XCTAssertEqual(UserPresenceOutcome.cancelled.eventJson, #""UserPresenceCheckCancelled""#)
    }

    func testUnavailableEventNamesTheUserPresenceTransport() {
        XCTAssertEqual(
            UserPresenceOutcome.unavailable.eventJson,
            #"{"HardwareUnavailable":{"transport":"user_presence"}}"#
        )
    }

    // MARK: - Capability

    func testCapabilityReportsUserPresenceSealing() {
        var hardware = DeviceHardware(
            hasNfc: false,
            hasBle: true,
            hasCamera: true,
            audio: .full,
            hasBiometrics: false,
            biometricType: nil,
            hasSecureEnclave: true,
            hasAccelerometer: true,
            hasInternet: true,
            hasUsbPort: false
        )
        XCTAssertTrue(buildDeviceCapabilitiesJson(hardware).contains(#""can_seal_user_presence":false"#))

        hardware.canSealUserPresence = true

        XCTAssertTrue(buildDeviceCapabilitiesJson(hardware).contains(#""can_seal_user_presence":true"#))
    }

    private func decodeCommands(_ json: String) throws -> [PresentationCommand] {
        try JSONDecoder().decode(
            PresentationCommandEnvelope.self,
            from: Data(json.utf8)
        ).commands
    }
}
