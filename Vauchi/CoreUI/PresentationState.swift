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
    private(set) var overlay: RevisionedOverlay?

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
                // Any surface replacement means navigation happened, so the
                // overlay dies with it — not only when the replaced surface is
                // the one it was raised over. Core clears its own
                // open-overlay state on every dispatch and sends no dismissal
                // when an item inside the menu navigates, so a surviving
                // overlay desynchronises the two: on an iPhone the menu stayed
                // drawn over the destination and the next menu tap
                // re-presented it instead of toggling shut.
                //
                // Commands arrive with ReplaceSurface before any
                // PresentOverlay in the same transaction, so this cannot clear
                // an overlay the same batch just raised.
                next.overlay = nil
            case let .setContextBar(bar, surfaceID):
                guard next.surfaces[surfaceID]?.revision == bar.revision else {
                    throw PresentationStateError.mismatchedContextBar(surfaceID)
                }
                next.bars[surfaceID] = bar
            case let .presentOverlay(overlay):
                guard next.surfaces[overlay.surfaceID]?.revision == overlay.revision else {
                    throw PresentationStateError.mismatchedOverlay(overlay.surfaceID)
                }
                next.overlay = overlay
            case let .dismissOverlay(surfaceID, _, kind):
                // Core rewrites a repeat PresentOverlay into this so the
                // context-bar buttons toggle. Matching on kind as well as
                // surface keeps a stale dismiss from closing an overlay Core
                // has since replaced.
                if let open = next.overlay,
                   open.surfaceID == surfaceID,
                   open.overlay.kind == kind {
                    next.overlay = nil
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
        overlay = nil
    }

    var activeSurfaceID: String? {
        profile?.activeSurface ?? surfaces.keys.sorted().first
    }

    var activeBar: PresentationContextBar? {
        activeSurfaceID.flatMap { bars[$0]?.bar }
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
