// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppleHw
import CommandContract
import EventContract
import Foundation

protocol AppleHardwarePort: AnyObject {
    var onEvent: ((Event) -> Void)? { get set }
    func execute(_ command: Command) -> Bool
}

extension AppleHardware: AppleHardwarePort {}

/// Called on the main thread, like AppleHardware's CoreLocation port.
final class LocationHardwareBridge {
    private let hardware: any AppleHardwarePort

    init(hardware: any AppleHardwarePort = AppleHardware(), report: @escaping (Result<String, Error>) -> Void) {
        self.hardware = hardware
        hardware.onEvent = { event in
            report(Result {
                try String(decoding: JSONEncoder().encode(event), as: UTF8.self)
            })
        }
    }

    func request(timeoutMs: UInt32) throws {
        let json = #"{"LocationRequest":{"timeout_ms":\#(timeoutMs)}}"#
        let command = try JSONDecoder().decode(Command.self, from: Data(json.utf8))
        _ = hardware.execute(command)
    }
}
