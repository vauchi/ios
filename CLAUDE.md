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

## Rules

- Follow Swift/iOS conventions
- Use SwiftUI for all new UI
- Native bindings via `vauchi-mobile-swift` SPM package (no local build needed)

## Structure

- `Vauchi/` - Main app source
- `VauchiTests/` - Test target
