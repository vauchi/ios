// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Vauchi
import XCTest

final class AudioOperationSlotTests: XCTestCase {
    func testStopInvalidatesWorkThatHasNotEnteredItsOwner() {
        let slot = AudioOperationSlot()
        let request = slot.reserve()
        slot.stop()
        var started = false
        slot.run(for: 0, request: request, start: { started = true }, stop: {})
        XCTAssertFalse(started)
        XCTAssertFalse(slot.isActive)
    }

    func testAnOlderPendingRequestCannotReplaceANewerOne() {
        let slot = AudioOperationSlot()
        let older = slot.reserve()
        let newer = slot.reserve()
        var observed: [Int] = []
        slot.run(for: 0, request: newer, start: { observed.append(2) }, stop: {})
        slot.run(for: 0, request: older, start: { observed.append(1) }, stop: {})
        XCTAssertEqual(observed, [2])
    }

    func testOnlyTheLatestUnstoppedRequestDeliversItsCallback() {
        let slot = AudioOperationSlot()
        let older = slot.reserve()
        let newer = slot.reserve()
        var delivered: [Int] = []
        XCTAssertFalse(slot.deliver(older) { delivered.append(1) })
        slot.run(for: 0, request: newer, start: {}, stop: {})
        XCTAssertTrue(slot.deliver(newer) { delivered.append(2) })
        slot.stop()
        XCTAssertFalse(slot.deliver(newer) { delivered.append(3) })
        XCTAssertEqual(delivered, [2])
    }

    // Feature: contact_exchange.feature — native audio resource lifetime.
    func testStopReleasesResourceAndWakesWorker() {
        let slot = AudioOperationSlot()
        let resource = ExclusiveAudioResource()
        let started = expectation(description: "started")
        let returned = expectation(description: "returned")
        defer { slot.stop() }
        DispatchQueue.global().async {
            do {
                try slot.run(for: 60, start: {
                    try resource.acquire(1)
                    started.fulfill()
                }, stop: { resource.release(1) })
            } catch { XCTFail("Unexpected start error: \(error)") }
            returned.fulfill()
        }
        wait(for: [started], timeout: 2)
        slot.stop()
        wait(for: [returned], timeout: 2)
        XCTAssertEqual(resource.owner, 0)
        XCTAssertFalse(slot.isActive)
    }

    func testReplacementReleasesOldResourceAndSurvivesOldReturn() {
        let slot = AudioOperationSlot()
        let resource = ExclusiveAudioResource()
        let firstStarted = expectation(description: "first started")
        let firstReturned = expectation(description: "first returned")
        let secondStarted = expectation(description: "second started")
        let secondReturned = expectation(description: "second returned")
        defer { slot.stop() }
        DispatchQueue.global().async {
            do {
                try slot.run(for: 60, start: {
                    try resource.acquire(1)
                    firstStarted.fulfill()
                }, stop: { resource.release(1) })
            } catch { XCTFail("Unexpected first error: \(error)") }
            firstReturned.fulfill()
        }
        wait(for: [firstStarted], timeout: 2)
        DispatchQueue.global().async {
            do {
                try slot.run(for: 60, start: {
                    try resource.acquire(2)
                    secondStarted.fulfill()
                }, stop: { resource.release(2) })
            } catch { XCTFail("Replacement reused occupied resource: \(error)") }
            secondReturned.fulfill()
        }
        wait(for: [secondStarted, firstReturned], timeout: 2)
        XCTAssertEqual(resource.owner, 2)
        XCTAssertTrue(slot.isActive)
        slot.stop()
        wait(for: [secondReturned], timeout: 2)
        XCTAssertEqual(resource.owner, 0)
        XCTAssertFalse(slot.isActive)
    }

    func testFailedStartReleasesPartialResource() {
        let slot = AudioOperationSlot()
        let resource = ExclusiveAudioResource()
        XCTAssertThrowsError(try slot.run(for: 60, start: {
            try resource.acquire(1)
            throw ExclusiveAudioResource.Failure.unavailable
        }, stop: { resource.release(1) })) { error in
            XCTAssertEqual(error as? ExclusiveAudioResource.Failure, .unavailable)
        }
        XCTAssertEqual(resource.owner, 0)
        XCTAssertFalse(slot.isActive)
    }

    func testStoppingOnePortPreservesTheOther() {
        let playback = AudioOperationSlot()
        let capture = AudioOperationSlot()
        let playbackStarted = expectation(description: "playback started")
        let captureStarted = expectation(description: "capture started")
        let playbackReturned = expectation(description: "playback returned")
        let captureReturned = expectation(description: "capture returned")
        defer { playback.stop(); capture.stop() }
        DispatchQueue.global().async {
            try? playback.run(for: 60, start: { playbackStarted.fulfill() }, stop: {})
            playbackReturned.fulfill()
        }
        DispatchQueue.global().async {
            try? capture.run(for: 60, start: { captureStarted.fulfill() }, stop: {})
            captureReturned.fulfill()
        }
        wait(for: [playbackStarted, captureStarted], timeout: 2)
        playback.stop()
        wait(for: [playbackReturned], timeout: 2)
        XCTAssertFalse(playback.isActive)
        XCTAssertTrue(capture.isActive)
        capture.stop()
        wait(for: [captureReturned], timeout: 2)
        XCTAssertFalse(capture.isActive)
    }
}

private final class ExclusiveAudioResource {
    enum Failure: Error { case occupied, unavailable }
    private let lock = NSLock()
    private var holder = 0

    var owner: Int {
        lock.lock()
        defer { lock.unlock() }
        return holder
    }

    func acquire(_ identity: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard holder == 0 else { throw Failure.occupied }
        holder = identity
    }

    func release(_ identity: Int) {
        lock.lock()
        defer { lock.unlock() }
        if holder == identity {
            holder = 0
        }
    }
}
