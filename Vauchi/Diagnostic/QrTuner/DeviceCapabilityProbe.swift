// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import UIKit
import VauchiMobile

/// Queries the front camera's hardware capabilities and builds a
/// `MobileDeviceCapabilityProfile` suitable for sweep-matrix generation.
enum DeviceCapabilityProbe {
    /// Probe the front-facing wide-angle camera and return its capability profile.
    ///
    /// Falls back to a minimal profile when no front camera is available.
    static func probe() -> MobileDeviceCapabilityProfile {
        let deviceModel = UIDevice.current.model

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            return fallbackProfile(deviceModel: deviceModel)
        }

        let format = device.activeFormat
        let formatDesc = format.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)

        let isoMin = Int32(format.minISO)
        let isoMax = Int32(format.maxISO)
        let evMin = Int32(device.minExposureTargetBias)
        let evMax = Int32(device.maxExposureTargetBias)

        var afModes: [String] = []
        if device.isFocusModeSupported(.locked) { afModes.append("locked") }
        if device.isFocusModeSupported(.autoFocus) { afModes.append("auto") }
        if device.isFocusModeSupported(.continuousAutoFocus) { afModes.append("continuous") }

        var awbModes: [String] = []
        if device.isWhiteBalanceModeSupported(.locked) { awbModes.append("locked") }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { awbModes.append("continuous") }
        if device.isWhiteBalanceModeSupported(.autoWhiteBalance) { awbModes.append("auto") }

        let fpsRanges = enumerateFpsRanges(device: device)
        let maxRes = enumerateMaxResolution(device: device, limit: 1920 * 1440)

        return MobileDeviceCapabilityProfile(
            platform: .ios,
            deviceModel: deviceModel,
            hardwareLevel: nil,
            isoRangeMin: isoMin,
            isoRangeMax: isoMax,
            exposureEvRangeMin: evMin,
            exposureEvRangeMax: evMax,
            afModes: afModes,
            awbModes: awbModes,
            fpsRanges: fpsRanges,
            maxResolutionWidth: maxRes.width,
            maxResolutionHeight: maxRes.height
        )
    }

    // MARK: - Private

    private static func enumerateFpsRanges(device: AVCaptureDevice) -> [MobileFpsRange] {
        var seen = Set<String>()
        var result: [MobileFpsRange] = []

        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                let key = "\(Int32(range.minFrameRate))-\(Int32(range.maxFrameRate))"
                if seen.insert(key).inserted {
                    result.append(MobileFpsRange(
                        min: Int32(range.minFrameRate),
                        max: Int32(range.maxFrameRate)
                    ))
                }
            }
        }

        return result.isEmpty ? [MobileFpsRange(min: 30, max: 30)] : result
    }

    private static func enumerateMaxResolution(
        device: AVCaptureDevice,
        limit: Int32
    ) -> (width: UInt32, height: UInt32) {
        var bestWidth: Int32 = 640
        var bestHeight: Int32 = 480
        var bestPixels: Int32 = bestWidth * bestHeight

        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let pixels = dims.width * dims.height
            if pixels > bestPixels, pixels <= limit {
                bestWidth = dims.width
                bestHeight = dims.height
                bestPixels = pixels
            }
        }

        return (UInt32(bestWidth), UInt32(bestHeight))
    }

    private static func fallbackProfile(deviceModel: String) -> MobileDeviceCapabilityProfile {
        MobileDeviceCapabilityProfile(
            platform: .ios,
            deviceModel: deviceModel,
            hardwareLevel: nil,
            isoRangeMin: nil,
            isoRangeMax: nil,
            exposureEvRangeMin: nil,
            exposureEvRangeMax: nil,
            afModes: ["auto"],
            awbModes: ["auto"],
            fpsRanges: [MobileFpsRange(min: 30, max: 30)],
            maxResolutionWidth: 640,
            maxResolutionHeight: 480
        )
    }
}
