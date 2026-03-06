// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import VauchiMobile

/// Per-frame decode result captured during a configuration sweep.
struct FrameResult {
    let decoded: Bool
    let latencyMs: Float
    let timestampNs: UInt64
}

/// Aggregated result of running a single camera configuration.
struct ConfigRunResult {
    let configId: UInt32
    let frames: [FrameResult]
    let thermalEvents: Int
}

/// Applies camera configurations to `AVCaptureDevice` and runs frame-capture sweeps.
enum CameraConfigTuner {
    /// Apply a `MobileCameraConfig` to the given capture device.
    ///
    /// Locks the device for configuration, sets ISO, exposure bias, focus mode,
    /// and white balance mode where supported, then unlocks.
    static func applyConfig(
        _ config: MobileCameraConfig,
        to device: AVCaptureDevice
    ) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        // ISO — only set if supported and value is present
        if let iso = config.iso,
           device.isExposureModeSupported(.custom) {
            let clampedIso = min(max(Float(iso), device.activeFormat.minISO),
                                 device.activeFormat.maxISO)
            device.setExposureModeCustom(
                duration: AVCaptureDevice.currentExposureDuration,
                iso: clampedIso,
                completionHandler: nil
            )
        }

        // Exposure bias
        if let ev = config.exposureEv {
            let clampedEv = min(max(Float(ev), device.minExposureTargetBias),
                                device.maxExposureTargetBias)
            device.setExposureTargetBias(clampedEv, completionHandler: nil)
        }

        // Focus mode
        switch config.focusMode {
        case "locked":
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
        case "continuous":
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        default:
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
        }

        // White balance mode
        switch config.whiteBalance {
        case "locked":
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
        case "continuous":
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        default:
            if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                device.whiteBalanceMode = .autoWhiteBalance
            }
        }
    }

    /// Run a single configuration for 60 frames with a 1.5 s stabilisation delay.
    ///
    /// Checks thermal state every 20 frames. If critical, waits for cooldown
    /// before resuming and increments `thermalEvents`.
    ///
    /// - Parameters:
    ///   - configId: The camera configuration ID being tested.
    ///   - decodeFrame: Closure that captures and decodes a single frame.
    /// - Returns: Aggregated run result with all frame data.
    static func runConfig(
        configId: UInt32,
        decodeFrame: () async -> FrameResult
    ) async -> ConfigRunResult {
        // Stabilisation delay
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        var frames: [FrameResult] = []
        var thermalEvents = 0
        let totalFrames = 60
        let thermalCheckInterval = 20

        for i in 0 ..< totalFrames {
            // Thermal check every 20 frames
            if i > 0, i % thermalCheckInterval == 0, ThermalMonitor.isCritical {
                thermalEvents += 1
                await ThermalMonitor.waitForCooldown()
            }

            let result = await decodeFrame()
            frames.append(result)
        }

        return ConfigRunResult(
            configId: configId,
            frames: frames,
            thermalEvents: thermalEvents
        )
    }

    /// Convert a `ConfigRunResult` into a `MobileTuningResult` for ranking.
    static func toTuningResult(
        run: ConfigRunResult,
        qrConfig: MobileQrConfig,
        actualIso: Int32?,
        actualExposureEv: Int32?
    ) -> MobileTuningResult {
        let decoded = run.frames.filter(\.decoded)
        let total = UInt32(run.frames.count)
        let decodedCount = UInt32(decoded.count)
        let decodeRate = total > 0 ? Float(decodedCount) / Float(total) : 0.0

        let latencies = decoded.map(\.latencyMs)
        let avgLatency = latencies.isEmpty ? 0.0 : latencies.reduce(0, +) / Float(latencies.count)

        let jitter: Float
        if latencies.count > 1 {
            let mean = avgLatency
            let variance = latencies.map { ($0 - mean) * ($0 - mean) }
                .reduce(0, +) / Float(latencies.count)
            jitter = variance.squareRoot()
        } else {
            jitter = 0.0
        }

        return MobileTuningResult(
            cameraConfigId: run.configId,
            qrErrorCorrection: qrConfig.errorCorrection,
            qrPayloadSizeBytes: qrConfig.payloadSizeBytes,
            qrModuleSizePx: qrConfig.moduleSizePx,
            decodeRate: decodeRate,
            avgLatencyMs: avgLatency,
            jitterMs: jitter,
            thermalEvents: UInt32(run.thermalEvents),
            framesTotal: total,
            framesDecoded: decodedCount,
            actualIso: actualIso,
            actualExposureEv: actualExposureEv
        )
    }
}
