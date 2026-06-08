// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreLocation
import VauchiPlatform

/// One-shot device location capture for the exchange "where we met"
/// annotation (ADR-051 capture-at-exchange).
///
/// Wraps `CLLocationManager`: requests when-in-use authorization, asks for a
/// single fix within the timeout, and reports the outcome exactly once as the
/// matching `MobileEvent` — `.locationResult`, `.permissionDenied(transport:
/// "location")`, or `.hardwareUnavailable(transport: "location")`. Core
/// (`AppEngine`) consumes the event and records `set_exchange_location`.
///
/// CC-23: the engine is driven by the resulting event; this edge object owns
/// only the CoreLocation plumbing. Tests assert the command starts a capture
/// (see `AppViewModel.locationRequestInFlight`), never the OS permission modal.
final class LocationService: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var onResult: ((MobileEvent) -> Void)?
    private var timeoutWork: DispatchWorkItem?
    private var finished = false

    /// Request a single location fix. `onResult` is invoked exactly once.
    func requestOneShot(timeoutMs: UInt32, onResult: @escaping (MobileEvent) -> Void) {
        self.onResult = onResult
        finished = false

        guard CLLocationManager.locationServicesEnabled() else {
            finish(.hardwareUnavailable(transport: "location"))
            return
        }

        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.manager = manager

        // Bound the wait: a missing fix within the timeout reports unavailable
        // so core clears its pending capture rather than hanging.
        let work = DispatchWorkItem { [weak self] in
            self?.finish(.hardwareUnavailable(transport: "location"))
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Int(timeoutMs)),
            execute: work
        )

        manager.requestWhenInUseAuthorization()
        // If authorization is already resolved, kick the fix immediately;
        // otherwise `locationManagerDidChangeAuthorization` drives it.
        requestIfAuthorized()
    }

    private func requestIfAuthorized() {
        guard let manager else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.permissionDenied(transport: "location"))
        case .notDetermined:
            break // wait for the authorization callback
        @unknown default:
            finish(.hardwareUnavailable(transport: "location"))
        }
    }

    private func finish(_ event: MobileEvent) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        timeoutWork = nil
        manager?.delegate = nil
        manager = nil
        let callback = onResult
        onResult = nil
        callback?(event)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        requestIfAuthorized()
    }

    func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.last else { return }
        let accuracy = loc.horizontalAccuracy >= 0 ? Float(loc.horizontalAccuracy) : nil
        finish(
            .locationResult(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                accuracyMeters: accuracy
            )
        )
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        finish(.hardwareUnavailable(transport: "location"))
    }
}
