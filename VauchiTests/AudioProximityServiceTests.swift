// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// AudioProximityServiceTests.swift
// Tests for AudioProximityService - ultrasonic proximity verification
// Based on: features/contact_exchange.feature

@testable import Vauchi
import XCTest

/// Tests for AudioProximityService
/// Based on: features/contact_exchange.feature - Scenario: Proximity verification via audio
final class AudioProximityServiceTests: XCTestCase {
    var audioService: AudioProximityService!

    override func setUpWithError() throws {
        audioService = AudioProximityService.shared
        // Ensure any previous audio is stopped
        audioService.stop()
    }

    override func tearDownWithError() throws {
        audioService.stop()
    }

    // MARK: - Capability Tests

    /// Scenario: Check device audio capability
    func testCheckCapability() {
        let capability = audioService.checkCapability()

        // Should return one of: "full", "emit_only", "receive_only", "none"
        let validCapabilities = ["full", "emit_only", "receive_only", "none"]
        XCTAssertTrue(validCapabilities.contains(capability),
                      "Capability should be one of \(validCapabilities), got: \(capability)")
    }

    /// Scenario: Capability reflects actual hardware
    func testCapabilityIsConsistent() {
        // Multiple calls should return same result
        let cap1 = audioService.checkCapability()
        let cap2 = audioService.checkCapability()
        let cap3 = audioService.checkCapability()

        XCTAssertEqual(cap1, cap2)
        XCTAssertEqual(cap2, cap3)
    }

    // MARK: - Active State Tests

    /// Scenario: Service starts inactive
    func testInitiallyInactive() {
        XCTAssertFalse(audioService.isActive(), "Service should start inactive")
    }

    /// Scenario: Stop when already stopped is safe
    func testStopWhenInactiveIsSafe() {
        audioService.stop()
        audioService.stop()
        audioService.stop()

        XCTAssertFalse(audioService.isActive(), "Should remain inactive after multiple stops")
    }

    // MARK: - Emit Signal Tests

    /// Scenario: Emit empty samples returns error
    func testEmitEmptySamplesReturnsError() {
        let result = audioService.emitSignal(samples: [], sampleRate: 44100)
        XCTAssertFalse(result.isEmpty, "Should return error message for empty samples")
    }

    /// Scenario: Emit valid samples (test with minimal audio)
    func testEmitValidSamples() {
        // Generate short test signal (100ms of 18kHz sine wave)
        let sampleRate: UInt32 = 44100
        let duration: Float = 0.1
        let frequency: Float = 18000
        let sampleCount = Int(Float(sampleRate) * duration)

        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0 ..< sampleCount {
            let t = Float(i) / Float(sampleRate)
            samples[i] = sin(2.0 * .pi * frequency * t) * 0.5
        }

        // In CI/test environment, this may fail due to no audio hardware
        // We just verify it handles gracefully
        let result = audioService.emitSignal(samples: samples, sampleRate: sampleRate)

        // Either succeeds (empty string) or returns an error message
        // Both are valid outcomes depending on environment
        if !result.isEmpty {
            print("AudioProximityService: Emit returned: \(result)")
        }
    }

    // MARK: - Receive Signal Tests

    /// Scenario: Receive with zero timeout fires callback with actual hardware rate
    func testReceiveZeroTimeout() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Audio recording not functional in iOS Simulator")
        #endif
        let expectation = XCTestExpectation(description: "callback fires")
        var capturedRate: UInt32 = 0

        audioService.receiveSignal(timeoutMs: 0, sampleRate: 44100) { _, recordedRate in
            capturedRate = recordedRate
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertGreaterThan(capturedRate, 0, "Should report actual hardware sample rate (typically 44100 or 48000)")
    }

    /// Scenario: Receive callback delivers samples in [-1.0, 1.0] range
    func testReceiveReturnsFloatArray() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Audio recording not functional in iOS Simulator")
        #endif
        let expectation = XCTestExpectation(description: "callback fires with samples")
        var capturedSamples: [Float] = []

        audioService.receiveSignal(timeoutMs: 50, sampleRate: 44100) { samples, _ in
            capturedSamples = samples
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        for sample in capturedSamples {
            XCTAssertGreaterThanOrEqual(sample, -1.0, "Sample should be >= -1.0")
            XCTAssertLessThanOrEqual(sample, 1.0, "Sample should be <= 1.0")
        }
    }

    /// Scenario: Recorded rate is reported even when device rate differs from requested rate
    func testReceiveReportsActualRecordedRate() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Audio recording not functional in iOS Simulator")
        #endif
        let expectation = XCTestExpectation(description: "callback fires")
        var capturedRate: UInt32 = 0

        // Request 44100 — device may record at 48000. Either is correct;
        // the contract is that the actual rate is reported, not silently coerced.
        audioService.receiveSignal(timeoutMs: 50, sampleRate: 44100) { _, recordedRate in
            capturedRate = recordedRate
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        // Common rates: 22050, 44100, 48000. Anything > 0 means we captured it.
        XCTAssertTrue([22050, 44100, 48000].contains(Int(capturedRate)) || capturedRate > 0,
                      "Recorded rate should be a real hardware rate, got: \(capturedRate)")
    }

    // MARK: - Integration Tests

    /// Scenario: Service can be started and stopped repeatedly
    func testStartStopCycle() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Audio recording not functional in iOS Simulator")
        #endif
        for _ in 0 ..< 3 {
            let samples = [Float](repeating: 0.5, count: 100)
            _ = audioService.emitSignal(samples: samples, sampleRate: 44100)
            audioService.stop()

            let expectation = XCTestExpectation(description: "receive callback")
            audioService.receiveSignal(timeoutMs: 10, sampleRate: 44100) { _, _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
            audioService.stop()
        }

        XCTAssertFalse(audioService.isActive(), "Should be inactive after stop")
    }

    /// Scenario: Concurrent operations are handled safely
    func testConcurrentOperationsSafe() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            _ = self.audioService.checkCapability()
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            self.audioService.stop()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Sample Rate Tests

    /// Scenario: Different requested sample rates are handled (device may not honor)
    func testDifferentSampleRates() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Audio recording not functional in iOS Simulator")
        #endif
        let sampleRates: [UInt32] = [22050, 44100, 48000]

        for rate in sampleRates {
            let expectation = XCTestExpectation(description: "rate \(rate)")
            audioService.receiveSignal(timeoutMs: 10, sampleRate: rate) { _, _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
            audioService.stop()
        }
    }
}
