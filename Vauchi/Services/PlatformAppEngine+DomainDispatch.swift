// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import VauchiPlatform

extension PlatformAppEngine {
    // MARK: - Identity / Bootstrap (C1)

    func createIdentity(displayName: String) throws {
        _ = try dispatchDomainCommand(
            command: .createIdentity(displayName: displayName)
        )
    }

    // MARK: - Content Updates

    /// Run the whole content-update cycle (check → apply → screen
    /// invalidation) in core and return its presentation-only outcome
    /// (core 0.51.69, `RunContentUpdateCycle`).
    func runContentUpdateCycle() throws -> MobileContentCycleOutcome {
        let result = try dispatchDomainCommand(command: .runContentUpdateCycle)
        guard case let .contentUpdateCycle(outcome) = result else {
            throw MobileError.Other(
                detail: "RunContentUpdateCycle: unexpected result variant"
            )
        }
        return outcome
    }

    // MARK: - Passcode (C6)

    func authenticate(password: String) throws -> MobileAuthMode {
        let result = try dispatchDomainCommand(command: .authenticate(password: password))
        guard case let .authMode(mode) = result else {
            throw MobileError.Other(
                detail: "Authenticate: unexpected result variant"
            )
        }
        return mode
    }

    // MARK: - Demo Contact (C8 partial)

    func initDemoContactIfNeeded() throws -> MobileDemoContact? {
        let result = try dispatchDomainCommand(command: .initDemoContactIfNeeded)
        guard case let .demoContactOpt(contact) = result else {
            throw MobileError.Other(
                detail: "InitDemoContactIfNeeded: unexpected result variant"
            )
        }
        return contact
    }
}
