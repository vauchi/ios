// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// Monitors the device thermal state and provides helpers for the sweep loop.
enum ThermalMonitor {
    private static let logger = Logger(
        subsystem: "com.vauchi.qrtuner",
        category: "thermal"
    )

    private static let cooldownPollNs: UInt64 = 5_000_000_000

    /// Returns `true` when the thermal state is `.serious` or `.critical`.
    static var isCritical: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    /// Returns `true` when the thermal state is `.nominal` or `.fair`.
    static var isSafeToResume: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .nominal || state == .fair
    }

    /// Human-readable description of the current thermal state.
    static var stateString: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// Polls until the thermal state drops to `.nominal` or `.fair`.
    ///
    /// Checks every 5 seconds. Logs each poll iteration.
    static func waitForCooldown() async {
        logger.info("Waiting for cooldown (current: \(stateString))")
        while !isSafeToResume {
            try? await Task.sleep(nanoseconds: cooldownPollNs)
            logger.info("Thermal state: \(stateString)")
        }
        logger.info("Cooldown complete")
    }
}
