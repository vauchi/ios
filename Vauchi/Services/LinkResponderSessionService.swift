// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import VauchiPlatform

/// Bridges the engine-cached `MobileLinkResponderSession` to the iOS UI.
///
/// Lifecycle:
///
/// 1. `VauchiApp` observes `coreScreen?.screenId == "link_responder_waiting"`.
/// 2. Calls `startIfNeeded()` — fetches the engine-cached session via
///    `appEngine.currentLinkResponderSession()`, attaches `self` as the
///    listener, calls `start()`. Idempotent — a second call while a
///    cycle thread is already running is a no-op.
/// 3. Cycle thread emits typed callbacks (`on_state_changed`,
///    `on_commands`, `on_finalized`, `on_failed`, `on_session_ended`)
///    from a background thread. The forwarder marshals every callback
///    to `@MainActor` before touching `coreVM` — `AppViewModel` is
///    main-actor isolated.
/// 4. When the user navigates away from the responder screen, core's
///    `after_screen_transition` cancel-on-leave fires
///    `MobileLinkResponderSession::cancel`, which surfaces an
///    `on_failed(Cancelled)` + `on_session_ended` pair. `Cancelled` is
///    a silent terminal — no toast.
///
/// The current draft surfaces toasts via
/// `AppViewModel.showToast(...)` and triggers `navigateBack()` on
/// terminal events. The `on_commands` callback is a TODO (the iOS
/// `RelayEscrow*` HTTP client is not yet implemented — see the
/// existing TODOs in `ExchangeCommandHandler`). Until that lands, the
/// responder cycle thread runs out the 5-minute polling deadline and
/// terminates with `PollingTimedOut`. The "could not save contact"
/// gap on success is tracked as a follow-up of
/// `_private/docs/problems/2026-04-27-deep-link-responder-flow`
/// Phase 2 — the on-disk Contact creation will move into core
/// (cycle-thread persistence, mirroring `MobileMultiStageSession::with_persistence`)
/// rather than being a frontend responsibility.
@MainActor
final class LinkResponderSessionService {
    private weak var coreVM: AppViewModel?

    /// Active session, set on `startIfNeeded()`. Cleared on
    /// `on_session_ended`. Held strong so the cycle thread keeps
    /// running for the duration of the screen — `currentLinkResponderSession`
    /// also caches it on the engine, so this is a redundant retain;
    /// kept for clarity and so `cancel()` is locally callable.
    private var session: MobileLinkResponderSession?
    private var listener: ListenerForwarder?

    init(coreVM: AppViewModel) {
        self.coreVM = coreVM
    }

    /// Idempotent. Pulls the engine-cached session, wires the listener,
    /// and spawns the cycle thread. Called by `VauchiApp` whenever the
    /// active screen becomes `link_responder_waiting`. A second call
    /// while a session is already in flight is a no-op.
    func startIfNeeded() {
        guard session == nil else { return }
        guard let coreVM else { return }
        do {
            guard let s = try coreVM.appEngine.currentLinkResponderSession() else {
                NSLog("[Vauchi] LinkResponder: no engine-cached session — wrong screen")
                return
            }
            let forwarder = ListenerForwarder(owner: self)
            listener = forwarder
            s.setListener(listener: forwarder)
            s.start()
            session = s
        } catch {
            NSLog("[Vauchi] LinkResponder: failed to start: \(error)")
        }
    }

    /// Tear down. Idempotent — safe to call when no session is active.
    /// Used as a defensive cleanup when the screen disappears even if
    /// core's `after_screen_transition` cancel-on-leave already ran.
    func stop() {
        session?.cancel()
        session = nil
        listener = nil
    }

    fileprivate func handleStateChanged(_: MobileLinkResponderState) {
        // Single-screen design — the waiting screen does not branch on
        // sub-state. This is the hook for a future progress indicator.
    }

    fileprivate func handleCommands(_: [MobileExchangeCommand]) {
        // TODO(2026-04-27 deep-link-responder Phase 2): dispatch
        // RelayEscrowDeposit / RelayEscrowCheck / RelayEscrowRetrieve
        // via a relay HTTP client. The existing iOS `ExchangeCommandHandler`
        // has TODOs for these; once that lands, route here too. Until
        // then the cycle thread's commands have no platform handler
        // and the polling deadline (~5 min) fires `PollingTimedOut`.
    }

    fileprivate func handleFinalized(_: Data) {
        // FOLLOW-UP: persist the contact via core. Phase 1.7 will move
        // persistence into the cycle thread (mirroring
        // `MobileMultiStageSession::with_persistence`), at which point
        // the listener trait will surface `on_finalized(contact_name)`
        // instead of raw `card_bytes` and the toast will include the
        // peer name. For now, surface a generic success toast.
        coreVM?.showToast("Contact added")
        coreVM?.navigateBack()
    }

    fileprivate func handleFailed(_ reason: MobileLinkResponderFailureReason) {
        let message: String? = switch reason {
        case .pollingTimedOut:
            "The sender hasn't responded yet"
        case .depositRejected:
            "This link has already been accepted"
        case .decryptError:
            "Could not decrypt the response"
        case .cancelled:
            // Silent terminal — user-initiated or navigate-back
            // cancellation. No toast; the navigate-back already
            // happened or is about to.
            nil
        @unknown default:
            "Exchange failed"
        }
        if let message {
            coreVM?.showToast(message)
            coreVM?.navigateBack()
        }
    }

    fileprivate func handleSessionEnded() {
        // Cycle thread has finished. Drop our local references — the
        // engine's `after_screen_transition` already cleared its slot
        // when navigation left the responder screen.
        session = nil
        listener = nil
    }
}

/// UniFFI callback forwarder. Bridges cycle-thread invocations to
/// `@MainActor` calls on the owning service. Holds a weak reference so
/// the listener does not retain the service across cycle-thread
/// lifetimes — UniFFI keeps the listener alive until the cycle thread
/// drops it via `on_session_ended`, after which the `weak owner`
/// becomes nil and further callbacks (none should fire after
/// `on_session_ended`) are no-ops.
private final class ListenerForwarder: LinkResponderSessionListener {
    weak var owner: LinkResponderSessionService?

    init(owner: LinkResponderSessionService) {
        self.owner = owner
    }

    func onStateChanged(state: MobileLinkResponderState) {
        Task { @MainActor [weak owner] in owner?.handleStateChanged(state) }
    }

    func onCommands(commands: [MobileExchangeCommand]) {
        Task { @MainActor [weak owner] in owner?.handleCommands(commands) }
    }

    func onFinalized(cardBytes: Data) {
        Task { @MainActor [weak owner] in owner?.handleFinalized(cardBytes) }
    }

    func onFailed(reason: MobileLinkResponderFailureReason) {
        Task { @MainActor [weak owner] in owner?.handleFailed(reason) }
    }

    func onSessionEnded() {
        Task { @MainActor [weak owner] in owner?.handleSessionEnded() }
    }
}
