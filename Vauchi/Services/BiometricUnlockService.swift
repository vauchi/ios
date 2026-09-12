// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LocalAuthentication
import VauchiPlatform

/// What the platform biometric prompt came back with, in the three shapes
/// Core's lock screen distinguishes (`Command::RequestBiometricUnlock` in
/// `core/vauchi-core/src/platform.rs`).
enum BiometricUnlockResult: Equatable {
    case succeeded
    /// No enrolled biometry, or none on this device.
    case unavailable
    case failed(String)
    /// The user dismissed the prompt; the lock screen stays as it was and
    /// Core hears nothing, since a cancel is not a hardware fault.
    case cancelled

    /// Core treats the outcome as a hardware event so the constant-time
    /// duress decision stays on its side (ADR-031).
    var mobileEvent: MobileEvent? {
        switch self {
        case .succeeded: .biometricUnlockSucceeded
        case .unavailable: .hardwareUnavailable(transport: Self.transport)
        case let .failed(error): .hardwareError(transport: Self.transport, error: error)
        case .cancelled: nil
        }
    }

    private static let transport = "biometric"
}

/// Seam for the biometric prompt so the dispatch can be exercised without
/// `LAContext`, which no unit test can drive.
protocol BiometricUnlockPrompting: AnyObject {
    func prompt(reason: String, completion: @escaping (BiometricUnlockResult) -> Void)
}

/// `LocalAuthentication`-backed prompt. Biometrics only, never the device
/// passcode fallback: Core offers this action because the shell reported
/// biometric hardware, and the app password path is Core's own.
final class LocalAuthenticationBiometricUnlock: BiometricUnlockPrompting {
    func prompt(reason: String, completion: @escaping (BiometricUnlockResult) -> Void) {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availabilityError)
        else {
            completion(.unavailable)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            completion(Self.result(success: success, error: error))
        }
    }

    private static func result(success: Bool, error: Error?) -> BiometricUnlockResult {
        if success { return .succeeded }
        guard let laError = error as? LAError else {
            return .failed(error?.localizedDescription ?? "Biometric authentication failed")
        }
        switch laError.code {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            return .cancelled
        case .biometryNotAvailable, .biometryNotEnrolled:
            return .unavailable
        default:
            return .failed(laError.localizedDescription)
        }
    }
}
