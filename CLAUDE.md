# CLAUDE.md - iOS App

Native iOS app using SwiftUI.

## Stack

- **Language**: Swift
- **UI**: SwiftUI
- **Build**: Xcode / Swift Package Manager
- **Native**: UniFFI bindings from `vauchi-mobile`

## Commands

```bash
./build-ios.sh                   # Build with bindings
xcodebuild -scheme Vauchi test   # Run tests
```

## Rules

- Follow Swift/iOS conventions
- Use SwiftUI for all new UI
- Native bindings via `vauchi-mobile` crate
- Run `code/scripts/build-bindings.sh` before building if core changed

## Structure

- `Vauchi/` - Main app source
- `VauchiTests/` - Test target
- `scripts/` - iOS-specific build scripts
