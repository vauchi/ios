// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreMotion
import Foundation

/// Accelerometer capture for the TapHoverShake "shake" co-location signal.
///
/// A Humble hardware adapter (ADR-031): it starts/stops on core's
/// `CommandDTO.accelerometerStart` / `.accelerometerStop` and streams each
/// reading back as raw milli-g values for the caller to wrap in
/// `MobileEvent.accelerometerData`. All correlation and decision logic lives
/// in core (`MultiStageSession`); this service only samples `CMMotionManager`.
///
/// Mirrors `AudioProximityService` — the other multi-stage proximity sensor.
final class AccelerometerProximityService {
    static let shared = AccelerometerProximityService()

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private(set) var isStreaming = false

    private init() {
        queue.name = "app.vauchi.accelerometer"
        queue.maxConcurrentOperationCount = 1
    }

    /// True iff the device exposes an accelerometer.
    var isAvailable: Bool {
        motionManager.isAccelerometerAvailable
    }

    /// Convert one axis reading in g to milli-g. `CMAcceleration` is already in
    /// g units (1 g at rest → 1000 milli-g), matching core's envelope shape,
    /// which quantizes the magnitude and clamps at 8 g.
    static func milliG(_ gValue: Double) -> Int32 {
        Int32((gValue * 1000.0).rounded())
    }

    /// Begin streaming accelerometer readings. Each reading invokes
    /// `onReading` with `(timestampMs, xMilliG, yMilliG, zMilliG)`. Idempotent;
    /// a no-op when the device has no accelerometer (core then times out the
    /// shake stage). The handler fires on a background queue — the caller hops
    /// to the main actor before touching core.
    func start(onReading: @escaping (UInt64, Int32, Int32, Int32) -> Void) {
        guard motionManager.isAccelerometerAvailable, !isStreaming else { return }
        isStreaming = true
        // ~50 Hz, matching Android's SENSOR_DELAY_GAME.
        motionManager.accelerometerUpdateInterval = 1.0 / 50.0
        motionManager.startAccelerometerUpdates(to: queue) { data, _ in
            guard let data else { return }
            let acceleration = data.acceleration
            // CMAccelerometerData.timestamp is seconds since boot; core needs
            // only a monotonic millisecond stamp for ordering, not wall-clock.
            let timestampMs = UInt64(max(0, data.timestamp) * 1000.0)
            onReading(
                timestampMs,
                Self.milliG(acceleration.x),
                Self.milliG(acceleration.y),
                Self.milliG(acceleration.z)
            )
        }
    }

    /// Stop streaming. Idempotent.
    func stop() {
        guard isStreaming else { return }
        isStreaming = false
        motionManager.stopAccelerometerUpdates()
    }
}
