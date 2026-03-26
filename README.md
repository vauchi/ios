<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

> **Mirror:** This repo is a read-only mirror of [gitlab.com/vauchi/ios](https://gitlab.com/vauchi/ios). Please open issues and merge requests there.

[![Pipeline](https://vauchi.gitlab.io/ios/badges/pipeline.svg)](https://gitlab.com/vauchi/ios/-/pipelines)
[![Coverage](https://vauchi.gitlab.io/ios/badges/coverage.svg)](https://gitlab.com/vauchi/ios/-/pipelines)
[![REUSE](https://api.reuse.software/badge/gitlab.com/vauchi/ios)](https://api.reuse.software/info/gitlab.com/vauchi/ios)

> [!WARNING]
> **Pre-Alpha Software** - This project is under heavy development and not ready for production use.
> APIs may change without notice. Use at your own risk.

# Vauchi iOS

Native iOS app for Vauchi - privacy-focused contact card exchange.

## Prerequisites

- macOS
- Xcode (download from [App Store](https://apps.apple.com/app/xcode/id497799835) or [developer.apple.com](https://developer.apple.com/download/all/))
- Rust (for building UniFFI bindings)

## Quick Setup

Run the setup script to configure Xcode:

```bash
./scripts/xcode-ide-setup.sh
```

This script will:
1. Verify Xcode installation
2. Accept the license agreement
3. Run first launch setup (installs required components)
4. Download iOS platform and simulators
5. Install Rust iOS targets for UniFFI builds

## Manual Setup

If you prefer manual setup or the script fails:

### 1. Install Xcode

**Option A - App Store:**
- Open App Store, search "Xcode", install

**Option B - Developer Portal (specific versions):**
1. Go to https://developer.apple.com/download/all/
2. Sign in with Apple ID
3. Download Xcode .xip file
4. Extract and move to `/Applications/Xcode.app`

### 2. Accept License Agreement

```bash
sudo xcodebuild -license accept
```

### 3. Install Components

```bash
xcodebuild -runFirstLaunch
```

### 4. Install iOS Platform

```bash
xcodebuild -downloadPlatform iOS
```

Or via Xcode: Settings → Components → iOS

### 5. Install Rust iOS Targets (for UniFFI)

```bash
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
```

## Building

### Command Line

```bash
# Build for simulator
xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Xcode

```bash
open Vauchi.xcodeproj
```

Then use Cmd+B to build, Cmd+R to run.

## Project Structure

```
vauchi-ios/
├── Vauchi.xcodeproj      # Xcode project
├── Package.swift          # Swift Package Manager manifest
├── scripts/
│   └── setup-xcode.sh     # Development environment setup
├── Vauchi/
│   ├── VauchiApp.swift   # App entry point
│   ├── ContentView.swift  # Root view
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── ContactsView.swift
│   │   ├── ContactDetailView.swift
│   │   ├── ExchangeView.swift
│   │   ├── QRScannerView.swift
│   │   ├── SettingsView.swift
│   │   └── SetupView.swift
│   ├── ViewModels/
│   │   └── VauchiViewModel.swift
│   └── Services/
│       ├── VauchiRepository.swift
│       └── KeychainService.swift
└── VauchiTests/
    ├── VauchiRepositoryTests.swift
    └── VauchiViewModelTests.swift
```

## Architecture

The iOS app follows MVVM architecture:

- **Views**: SwiftUI views for UI
- **ViewModels**: Business logic and state management
- **Services**: Data access (VauchiRepository wraps UniFFI bindings)

The app uses `vauchi-platform` UniFFI bindings to call the Rust `vauchi-core` library for all cryptographic operations and data storage.

## Troubleshooting

### "No available devices matched the request"
Install iOS simulators:
```bash
xcodebuild -downloadPlatform iOS
```

### "You have not agreed to the Xcode license"
```bash
sudo xcodebuild -license accept
```

### "CoreSimulator.framework not found"
```bash
xcodebuild -runFirstLaunch
```

### Rust targets missing
```bash
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
```

## Related Repositories

| Repository | Description |
|------------|-------------|
| [vauchi/code](https://gitlab.com/vauchi/code) | Core Rust library (source of UniFFI bindings) |
| [vauchi/android](https://gitlab.com/vauchi/android) | Android app (Kotlin/Compose) |
| [vauchi/docs](https://gitlab.com/vauchi/docs) | Documentation |
| [vauchi/dev-tools](https://gitlab.com/vauchi/dev-tools) | Build scripts and workspace tools |

## ⚠️ Mandatory Development Rules

**TDD**: Red→Green→Refactor. Test FIRST or delete code and restart.

**Structure**: `src/` = production code only. `tests/` = tests only. Siblings, not nested.

See [CLAUDE.md](../CLAUDE.md) for additional mandatory rules.

## Contributing

1. Check [vauchi/docs](https://gitlab.com/vauchi/docs) for architecture decisions
2. Follow Apple's Human Interface Guidelines
3. Write tests for new features
4. Core library changes go to [vauchi/code](https://gitlab.com/vauchi/code)

## Support the Project

Vauchi is open source and community-funded — no VC money, no data harvesting.

- [GitHub Sponsors](https://github.com/sponsors/vauchi)
- [Liberapay](https://liberapay.com/Vauchi/donate)
- [Supporters](https://docs.vauchi.app/about/supporters/) for sponsorship tiers

## License

GPL-3.0-or-later
