// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Models.swift — re-exports the shared CoreUIModels package.
//
// All `ScreenModel` / `Component` / `UserAction` / `ActionResult` /
// `DesignTokens` types previously defined inline now live in the
// cross-platform `CoreUIModels` target shipped by
// `vauchi-platform-swift` (≥ 0.21.7). This file keeps the import
// site stable so every consumer under `Vauchi/CoreUI/**` picks up
// the types without a per-file `import CoreUIModels` edit.
//
// macOS consumes the same shared package — see
// `_private/docs/problems/2026-04-22-shared-coreui-models-package/`.

@_exported import CoreUIModels
