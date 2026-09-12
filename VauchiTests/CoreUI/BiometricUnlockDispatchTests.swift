// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Core's lock screen answers its biometric action with
// `Command::RequestBiometricUnlock` (`core/vauchi-app/src/ui/lock_screen.rs`)
// and expects the shell to run the platform prompt, then report back as a
// hardware event: `BiometricUnlockSucceeded`, or `HardwareUnavailable` /
// `HardwareError` when the prompt cannot succeed
// (`core/vauchi-core/src/platform.rs`, ADR-066).
//
// CC-23: the prompt is a spy — `LAContext` cannot be driven from a unit
// test — so these pin the decode, the dispatch seam, and the exact event
// JSON each outcome hands `dispatchJson`.
//
// Traces to: features/app_lock.feature

@testable import Vauchi
import VauchiPlatform
import XCTest

@MainActor
final class BiometricUnlockDispatchTests: XCTestCase {
    private final class BiometricPromptSpy: BiometricUnlockPrompting {
        var reasons: [String] = []
        var capturedCompletion: ((BiometricUnlockResult) -> Void)?

        func prompt(reason: String, completion: @escaping (BiometricUnlockResult) -> Void) {
            reasons.append(reason)
            capturedCompletion = completion
        }
    }

    private var tempDir: URL!
    private var repo: VauchiRepository!
    private var viewModel: AppViewModel!
    private var spy: BiometricPromptSpy!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        repo = try VauchiRepository(dataDir: tempDir.path)
        try repo.createIdentity(displayName: "Biometric Dispatch Test")
        viewModel = AppViewModel(appEngine: repo.appEngine)
        spy = BiometricPromptSpy()
        viewModel.biometricUnlockService = spy
    }

    override func tearDownWithError() throws {
        viewModel = nil
        repo = nil
        spy = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRequestBiometricUnlockDecodesAsItsOwnCommand() throws {
        let commands = try decodeCommands(#"{"commands":["RequestBiometricUnlock"]}"#)

        guard case .requestBiometricUnlock = try XCTUnwrap(commands.first) else {
            return XCTFail("expected .requestBiometricUnlock, got \(commands)")
        }
    }

    func testUnknownStringCommandStillDecodesAsPlatformEffect() throws {
        let commands = try decodeCommands(#"{"commands":["SomethingCoreAddedLater"]}"#)

        guard case let .platformEffect(variant, payload) = try XCTUnwrap(commands.first) else {
            return XCTFail("unknown kinds must stay tolerated, got \(commands)")
        }
        XCTAssertEqual(variant, "SomethingCoreAddedLater")
        XCTAssertNil(payload)
    }

    func testRequestBiometricUnlockRunsThePromptWithAReason() {
        viewModel.receivePresentationEnvelope(#"{"commands":["RequestBiometricUnlock"]}"#)

        XCTAssertEqual(spy.reasons.count, 1)
        XCTAssertEqual(spy.reasons.first?.isEmpty, false, "LAContext refuses an empty reason")
        XCTAssertNil(viewModel.alertMessage, "the command must not surface as a presentation error")
    }

    func testAnUnrelatedCommandDoesNotPrompt() {
        viewModel.receivePresentationEnvelope(#"{"commands":["PerformNativeBack"]}"#)

        XCTAssertEqual(spy.reasons, [])
    }

    func testSuccessReportsTheBiometricUnlockSucceededEvent() {
        XCTAssertEqual(
            BiometricUnlockResult.succeeded.mobileEvent.toEventJson(),
            #""BiometricUnlockSucceeded""#
        )
    }

    func testMissingHardwareReportsHardwareUnavailable() {
        XCTAssertEqual(
            BiometricUnlockResult.unavailable.mobileEvent.toEventJson(),
            #"{"HardwareUnavailable":{"transport":"biometric"}}"#
        )
    }

    func testFailureReportsHardwareErrorWithItsMessage() {
        XCTAssertEqual(
            BiometricUnlockResult.failed("Biometry is locked out").mobileEvent.toEventJson(),
            #"{"HardwareError":{"transport":"biometric","error":"Biometry is locked out"}}"#
        )
    }

    /// The completion forwards into the engine without trapping; Core's
    /// handling of the event is covered by its own lock-screen tests.
    func testPromptCompletionForwardsIntoTheEngine() {
        viewModel.receivePresentationEnvelope(#"{"commands":["RequestBiometricUnlock"]}"#)

        spy.capturedCompletion?(.unavailable)
        XCTAssertEqual(spy.reasons.count, 1)
    }

    private func decodeCommands(_ json: String) throws -> [PresentationCommand] {
        try JSONDecoder().decode(
            PresentationCommandEnvelope.self,
            from: Data(json.utf8)
        ).commands
    }
}
