<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# CLAUDE.md - iOS App

Native iOS app: SwiftUI, Xcode/SPM, UniFFI bindings via `vauchi-mobile-swift`.

## Rules

- Use SwiftUI for all new UI
- Snapshot tests run on 2x simulator (iPhone SE 3) for baselines to match
- Pre-MR: `just check-ios` (or `xcodegen generate && xcodebuild ... build test`)
