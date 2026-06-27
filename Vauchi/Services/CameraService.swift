// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import VauchiPlatform

/// Pure mapping from camera authorization status to the action a capture site
/// should take. Mirrors `LocationService.decision(for:)` so the scattered
/// camera sites share one OS-decision rule instead of each re-deriving it, and
/// so a definitive denial is forwarded to core as a hardware event (T0.5; the
/// iOS counterpart of Android T0.3).
///
/// Caseless `enum` (not a `class` like `LocationService`): there is no shared
/// session/delegate lifecycle to own — each capture site owns its own
/// `AVCaptureSession` — so this seam is purely the stateless decision mapper.
/// Do not "fix" it into a class.
///
/// CC-23: the seam is OS-free and unit-tested per status; the live
/// `AVCaptureDevice` prompt/session flow is OS-tested, never polled.
enum CameraService {
    /// The wire transport label core matches on (design §4). Lowercase.
    static let transport = "camera"

    enum AuthorizationDecision: Equatable {
        /// `.authorized` — start the capture session.
        case proceed
        /// `.notDetermined` — `requestAccess` drives the result.
        case awaitCallback
        /// A definitive denial — forward this event to core.
        case finish(MobileEvent)
    }

    /// Map the current authorization status to the action to take.
    static func decision(for status: AVAuthorizationStatus) -> AuthorizationDecision {
        switch status {
        case .authorized:
            return .proceed
        case .denied, .restricted:
            return .finish(.permissionDenied(transport: transport))
        case .notDetermined:
            return .awaitCallback
        @unknown default:
            // Treat an unknown status as a (recoverable) denial rather than
            // proceeding: proceeding would attempt a session setup that fails
            // silently with no event — the exact "waits forever" bug this
            // fixes. Surfacing it via the recoverable CameraGate path is the
            // safe default. (Unreachable on shipping iOS.)
            return .finish(.permissionDenied(transport: transport))
        }
    }

    /// The decision after `AVCaptureDevice.requestAccess` resolves a
    /// `.notDetermined` prompt. `granted == false` is the iOS analogue of the
    /// Android launcher's `granted == false` (T0.3 §1): the post-decision
    /// boundary and the only place a camera denial is emitted.
    static func decision(forGranted granted: Bool) -> AuthorizationDecision {
        granted ? .proceed : .finish(.permissionDenied(transport: transport))
    }
}
