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
                if let previous = next.surfaces[surface.surfaceID],
                   surface.revision <= previous.revision {
                    throw PresentationStateError.staleSurface(surface.surfaceID)
                }
                next.surfaces[surface.surfaceID] = surface
                next.bars.removeValue(forKey: surface.surfaceID)
                if next.overlay?.surfaceID == surface.surfaceID {
                    next.overlay = nil
                }
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
