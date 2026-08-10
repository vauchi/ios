// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum PresentationStateError: Error, Equatable {
    case staleSurface(String)
    case mismatchedContextBar(String)
    case mismatchedOverlay(String)
    case unknownProfileSurface(String)
}

struct PresentationState {
    private(set) var surfaces: [String: PresentationSurface] = [:]
    private(set) var bars: [String: RevisionedContextBar] = [:]
    private(set) var profile: PresentationProfile?
    private(set) var overlays: [String: RevisionedOverlay] = [:]

    mutating func apply(
        _ commands: [PresentationCommand]
    ) throws -> [PresentationCommand] {
        var next = self
        var effects: [PresentationCommand] = []

        for command in commands {
            switch command {
            case let .replaceSurface(surface):
                // Core's revision advances only on user actions, so racing
                // full rebuilds (wakeup re-load, invalidation dispatch)
                // legitimately re-emit the same surface at the same
                // revision. Only a strictly older revision is stale; equal
                // re-applies, last-writer wins.
                if let previous = next.surfaces[surface.surfaceID],
                   surface.revision < previous.revision {
                    throw PresentationStateError.staleSurface(surface.surfaceID)
                }
                next.surfaces[surface.surfaceID] = surface
                next.bars.removeValue(forKey: surface.surfaceID)
                // Only the overlay raised over *this* surface dies with it.
                // A broader "any ReplaceSurface clears" rule was tried and
                // reverted: it removed an overlay raised earlier in the same
                // transaction, so the navigation menu never appeared
                // (vauchi/ios!630, test:ui "Navigation overlay should list
                // destinations", twice). Keying by surface keeps that
                // ordering assumption out of the rule.
                next.overlays.removeValue(forKey: surface.surfaceID)
            case let .setContextBar(bar, surfaceID):
                guard next.surfaces[surfaceID]?.revision == bar.revision else {
                    throw PresentationStateError.mismatchedContextBar(surfaceID)
                }
                next.bars[surfaceID] = bar
            case let .presentOverlay(overlay):
                guard next.surfaces[overlay.surfaceID]?.revision == overlay.revision else {
                    throw PresentationStateError.mismatchedOverlay(overlay.surfaceID)
                }
                next.overlays[overlay.surfaceID] = overlay
            case let .dismissOverlay(surfaceID, _, kind):
                // Core rewrites a repeat PresentOverlay into this so the
                // context-bar buttons toggle. Matching on kind as well as
                // surface keeps a stale dismiss from closing an overlay Core
                // has since replaced.
                if next.overlays[surfaceID]?.overlay.kind == kind {
                    next.overlays.removeValue(forKey: surfaceID)
                }
            case let .setPresentationProfile(profile):
                next.profile = profile
            default:
                effects.append(command)
            }
        }

        if let profile = next.profile {
            let referenced = [
                profile.primarySurface,
                profile.activeSurface,
                profile.detailSurface,
            ].compactMap { $0 }
            if let missing = referenced.first(where: { next.surfaces[$0] == nil }) {
                throw PresentationStateError.unknownProfileSurface(missing)
            }
        }

        self = next
        return effects
    }

    mutating func dismissOverlay() {
        guard let activeSurfaceID else { return }
        overlays.removeValue(forKey: activeSurfaceID)
    }

    var activeSurfaceID: String? {
        profile?.activeSurface ?? surfaces.keys.sorted().first
    }

    var activeBar: PresentationContextBar? {
        activeSurfaceID.flatMap { bars[$0]?.bar }
    }

    /// The overlay to render, resolved through the active surface so a menu
    /// raised over one surface never stays drawn over the next one. Core
    /// sends no dismissal when a destination is chosen — it clears its own
    /// open-overlay state and expects each shell to scope the overlay the
    /// way `activeBar` already scopes the context bar
    /// (`2026-08-07-ios-stale-overlay-and-raw-error-alert`).
    var activeOverlay: RevisionedOverlay? {
        activeSurfaceID.flatMap { overlays[$0] }
    }

    /// Removes and returns overlays the active surface has left behind, so
    /// the caller can report each one to Core as dismissed.
    ///
    /// Core forgets its own open-overlay state *only* when the shell reports
    /// `OverlayDismissed` (`AppEngine::clear_open_overlay`); nothing else
    /// clears it. Scoping an overlay off screen without reporting it would
    /// leave Core's toggle believing that menu is still open, and
    /// `resolve_overlay_toggle` would then rewrite the next request for it
    /// into a dismissal — the menu would stop opening at all. Core's own
    /// comment names this: "the next activation would toggle closed against
    /// state that no longer matches the screen".
    mutating func takeOverlaysLeftBehind() -> [RevisionedOverlay] {
        guard let activeSurfaceID else { return [] }
        let leftBehind = overlays
            .filter { $0.key != activeSurfaceID }
            .values
            .sorted { $0.surfaceID < $1.surfaceID }
        for overlay in leftBehind {
            overlays.removeValue(forKey: overlay.surfaceID)
        }
        return leftBehind
    }

    var visibleSurfaceIDs: [String] {
        guard let profile else {
            return activeSurfaceID.map { [$0] } ?? []
        }
        if profile.paneLayout == .single {
            return [profile.activeSurface]
        }
        return [
            profile.primarySurface,
            profile.detailSurface,
        ].compactMap { $0 }
    }
}
