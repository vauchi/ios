// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import CommandContract
import EventContract
import Foundation
@testable import Vauchi
import XCTest

final class LocationHardwareBridgeTests: XCTestCase {
    func test_request_preserves_cores_timeout() throws {
        let hardware = RecordingHardware()
        let bridge = LocationHardwareBridge(hardware: hardware) { _ in }

        try bridge.request(timeoutMs: UInt32.max)

        let command = try XCTUnwrap(hardware.commands.first)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? NSDictionary
        XCTAssertEqual(json, ["LocationRequest": ["timeout_ms": UInt32.max]])
        XCTAssertEqual(hardware.commands.count, 1)
    }

    func test_observations_are_forwarded_as_canonical_event_json() throws {
        for json in [
            #"{"LocationResult":{"latitude":47.3769,"longitude":8.5417,"accuracy_meters":12.5}}"#,
            #"{"LocationResult":{"latitude":0,"longitude":0}}"#,
            #"{"PermissionDenied":{"transport":"location"}}"#,
            #"{"HardwareUnavailable":{"transport":"location"}}"#,
        ] {
            let hardware = RecordingHardware()
            var reports: [Result<String, Error>] = []
            let bridge = LocationHardwareBridge(hardware: hardware) { reports.append($0) }
            try bridge.request(timeoutMs: 5000)

            try hardware.onEvent?(JSONDecoder().decode(Event.self, from: Data(json.utf8)))

            XCTAssertEqual(reports.count, 1)
            let forwarded = try XCTUnwrap(reports.first).get()
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: Data(forwarded.utf8)) as? NSDictionary,
                try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
            )
        }
    }

    func test_unencodable_observation_reports_an_error() throws {
        let hardware = RecordingHardware()
        var reports: [Result<String, Error>] = []
        let bridge = LocationHardwareBridge(hardware: hardware) { reports.append($0) }
        try bridge.request(timeoutMs: 5000)
        let event = try JSONDecoder().decode(Event.self, from: Data(
            #"{"LocationResult":{"latitude":0,"longitude":0}}"#.utf8
        ))
        guard case let .eventClass(payload) = event, let location = payload.locationResult else {
            return XCTFail("location fixture did not decode")
        }
        hardware.onEvent?(.eventClass(payload.with(locationResult: location.with(latitude: .nan))))

        XCTAssertEqual(reports.count, 1)
        guard case .failure = try XCTUnwrap(reports.first) else {
            return XCTFail("a non-finite coordinate must not be dispatched to Core")
        }
    }
}

private final class RecordingHardware: AppleHardwarePort {
    var onEvent: ((Event) -> Void)?
    var commands: [Command] = []

    func execute(_ command: Command) -> Bool {
        commands.append(command)
        return true
    }
}
