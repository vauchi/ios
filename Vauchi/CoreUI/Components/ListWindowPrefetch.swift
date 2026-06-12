// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Window-move policy for windowed Component::List emissions (Track B
// of 2026-06-11-contacts-list-eager-render-anr).

/// Rows of cushion between the visible region and the loaded window's
/// edge before a re-slice is requested (~50 per the windowing design).
let listWindowPrefetchMargin = 50

/// Returns the offset to request from core, or nil when the visible
/// region is comfortably inside the loaded window (or the emission is
/// unwindowed). Targets keep the currently visible rows inside the new
/// window so row identity holds across the re-slice. Mirrors the
/// Android policy in `ListWindowPrefetch.kt` — both frontends must
/// move windows identically for core's clamping to behave the same.
func listWindowTarget(
    firstVisible: Int,
    lastVisible: Int,
    offset: Int,
    window: Int,
    totalCount: Int,
    margin: Int = listWindowPrefetchMargin
) -> Int? {
    guard totalCount > window else { return nil }
    if lastVisible >= offset + window - margin, offset + window < totalCount {
        let target = min(max(lastVisible - margin, 0), totalCount - window)
        return target == offset ? nil : target
    }
    if firstVisible <= offset + margin, offset > 0 {
        let target = max(firstVisible - (window - margin), 0)
        return target == offset ? nil : target
    }
    return nil
}
