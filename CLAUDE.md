<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# CLAUDE.md - iOS App

Native iOS app using SwiftUI.

## Stack

- **Language**: Swift
- **UI**: SwiftUI
- **Build**: Xcode / Swift Package Manager
- **Native**: UniFFI bindings via `vauchi-mobile-swift` SPM package

## Commands

```bash
xcodegen generate                # Regenerate Xcode project
xcodebuild -scheme Vauchi test   # Run tests
```

## Pre-MR Checklist

Run before submitting a merge request:

```bash
# From workspace root:
just check-ios

# Or manually from ios/:
xcodegen generate
xcodebuild -project Vauchi.xcodeproj -scheme Vauchi -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -clonedSourcePackagesDirPath .spm-packages build test

# Snapshot tests MUST run on a 2x simulator (iPhone SE 3) for baselines to match:
xcodebuild -project Vauchi.xcodeproj -scheme Vauchi -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone SE 3' \
  -only-testing:VauchiSnapshotTests \
  -clonedSourcePackagesDirPath .spm-packages test
```

CI runs the same checks (lint, build, test) on MR pipelines. No `allow_failure` — all jobs must pass.

## Rules

- Follow Swift/iOS conventions
- Use SwiftUI for all new UI
- Native bindings via `vauchi-mobile-swift` SPM package (no local build needed)

## Structure

- `Vauchi/` - Main app source
- `VauchiTests/` - Test target
