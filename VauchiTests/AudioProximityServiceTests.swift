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

    /// Scenario: Receive with zero timeout returns immediately
    func testReceiveZeroTimeout() {
        let samples = audioService.receiveSignal(timeoutMs: 0, sampleRate: 44100)

        // Should return empty or minimal samples with 0 timeout
        // This is environment-dependent
        XCTAssertNotNil(samples, "Should return array (may be empty)")
    }

    /// Scenario: Receive returns float array
    func testReceiveReturnsFloatArray() {
        // Very short recording - 50ms
        let samples = audioService.receiveSignal(timeoutMs: 50, sampleRate: 44100)

        // Verify samples are in valid range if any were recorded
        for sample in samples {
            XCTAssertGreaterThanOrEqual(sample, -1.0, "Sample should be >= -1.0")
            XCTAssertLessThanOrEqual(sample, 1.0, "Sample should be <= 1.0")
        }
    }

    // MARK: - Integration Tests

    /// Scenario: Service can be started and stopped repeatedly
    func testStartStopCycle() {
        for _ in 0 ..< 3 {
            // Start emit
            let samples = [Float](repeating: 0.5, count: 100)
            _ = audioService.emitSignal(samples: samples, sampleRate: 44100)
            audioService.stop()

            // Start receive
            _ = audioService.receiveSignal(timeoutMs: 10, sampleRate: 44100)
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

    /// Scenario: Different sample rates are handled
    func testDifferentSampleRates() {
        let sampleRates: [UInt32] = [22050, 44100, 48000]

        for rate in sampleRates {
            let samples = audioService.receiveSignal(timeoutMs: 10, sampleRate: rate)
            // Should not crash with different sample rates
            XCTAssertNotNil(samples)
            audioService.stop()
        }
    }
}
