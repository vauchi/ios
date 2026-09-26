// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
    /// `--simulate-camera` reports a camera the simulator does not have, so
    /// Core's exchange gate offers Glance and the store-screenshot job can
    /// reach the QR screen. Only the reported capability changes; Core still
    /// decides which modes to offer.
    func applyDebugCapabilityOverrides(_ hardware: DeviceHardware, arguments: [String]) -> DeviceHardware {
        var hardware = hardware
        if arguments.contains("--simulate-camera") {
            hardware.hasCamera = true
        }
        return hardware
    }
#endif
