// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    import Foundation
    import UIKit

    private let kTag = "ULTRASONIC_DIAG"

    enum DiagnosticLogger {
        static func logResult(
            test: String, track: String,
            frequencyHz: Int? = nil, snrDb: Double? = nil,
            magnitudeDb: Double? = nil, detected: Bool? = nil,
            audioMode: String? = nil, message: String? = nil
        ) {
            var dict: [String: Any] = [
                "test": test,
                "track": track,
                "device": UIDevice.current.model,
                "ts": ISO8601DateFormatter().string(from: Date()),
            ]
            if let f = frequencyHz { dict["freq_hz"] = f }
            if let s = snrDb { dict["snr_db"] = String(format: "%.1f", s) }
            if let m = magnitudeDb { dict["magnitude_db"] = String(format: "%.1f", m) }
            if let d = detected { dict["detected"] = d }
            if let a = audioMode { dict["audio_mode"] = a }
            if let msg = message { dict["message"] = msg }

            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let json = String(data: data, encoding: .utf8) {
                NSLog("[%@] %@", kTag, json)
            }
        }

        static func logError(test: String, track: String, error: String) {
            let dict: [String: Any] = [
                "test": test, "track": track,
                "device": UIDevice.current.model,
                "ts": ISO8601DateFormatter().string(from: Date()),
                "error": error,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let json = String(data: data, encoding: .utf8) {
                NSLog("[%@] ERROR %@", kTag, json)
            }
        }
    }
#endif
