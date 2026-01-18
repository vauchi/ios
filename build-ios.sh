#!/bin/bash
# Build script for Vauchi iOS - compiles Rust library and generates Swift bindings
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MOBILE_CRATE="$PROJECT_ROOT/vauchi-mobile"
IOS_DIR="$SCRIPT_DIR"
GENERATED_DIR="$IOS_DIR/Vauchi/Generated"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo_step "Checking prerequisites..."

    if ! command -v rustup &> /dev/null; then
        echo_error "rustup not found. Please install Rust: https://rustup.rs"
        exit 1
    fi

    if ! command -v cargo &> /dev/null; then
        echo_error "cargo not found. Please install Rust: https://rustup.rs"
        exit 1
    fi

    # Check for Xcode (not just Command Line Tools)
    XCODE_PATH=$(xcode-select -p 2>/dev/null)
    if [[ "$XCODE_PATH" == "/Library/Developer/CommandLineTools" ]]; then
        echo_error "Full Xcode is required for iOS builds (not just Command Line Tools)"
        echo_error "Install Xcode from the App Store, then run:"
        echo_error "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi

    if ! xcrun --sdk iphoneos --show-sdk-path &> /dev/null; then
        echo_error "iOS SDK not found. Please install Xcode with iOS support."
        exit 1
    fi

    echo_step "Using Xcode at: $XCODE_PATH"
    echo_step "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 'not found')"

    # Check for iOS targets
    if ! rustup target list --installed | grep -q "aarch64-apple-ios"; then
        echo_step "Adding iOS targets..."
        rustup target add aarch64-apple-ios
        rustup target add aarch64-apple-ios-sim
        rustup target add x86_64-apple-ios
    fi
}

# Build for iOS device (arm64)
build_device() {
    echo_step "Building for iOS device (aarch64-apple-ios)..."
    cargo build -p vauchi-mobile --target aarch64-apple-ios --release
}

# Build for iOS simulator (arm64 + x86_64)
build_simulator() {
    echo_step "Building for iOS simulator (aarch64-apple-ios-sim)..."
    cargo build -p vauchi-mobile --target aarch64-apple-ios-sim --release

    echo_step "Building for iOS simulator (x86_64-apple-ios)..."
    cargo build -p vauchi-mobile --target x86_64-apple-ios --release
}

# Create fat library for simulator (combines arm64 and x86_64)
create_simulator_fat_lib() {
    echo_step "Creating fat library for simulator..."

    local SIM_ARM64="$PROJECT_ROOT/target/aarch64-apple-ios-sim/release/libvauchi_mobile.a"
    local SIM_X64="$PROJECT_ROOT/target/x86_64-apple-ios/release/libvauchi_mobile.a"
    local FAT_LIB="$PROJECT_ROOT/target/ios-simulator/release/libvauchi_mobile.a"

    mkdir -p "$(dirname "$FAT_LIB")"
    lipo -create "$SIM_ARM64" "$SIM_X64" -output "$FAT_LIB"
}

# Generate Swift bindings using UniFFI
generate_bindings() {
    echo_step "Generating Swift bindings..."

    mkdir -p "$GENERATED_DIR"

    # Build the uniffi-bindgen binary
    cargo build -p vauchi-mobile --bin uniffi-bindgen --release

    # Generate Swift bindings from the device library
    "$PROJECT_ROOT/target/release/uniffi-bindgen" generate \
        --library "$PROJECT_ROOT/target/aarch64-apple-ios/release/libvauchi_mobile.a" \
        --language swift \
        --out-dir "$GENERATED_DIR"

    echo_step "Generated bindings in $GENERATED_DIR"
}

# Create XCFramework
create_xcframework() {
    echo_step "Creating XCFramework..."

    local XCFRAMEWORK_DIR="$IOS_DIR/Frameworks"
    local XCFRAMEWORK_PATH="$XCFRAMEWORK_DIR/VauchiMobile.xcframework"
    local DEVICE_LIB="$PROJECT_ROOT/target/aarch64-apple-ios/release/libvauchi_mobile.a"
    local SIM_FAT_LIB="$PROJECT_ROOT/target/ios-simulator/release/libvauchi_mobile.a"

    # Remove old framework if exists
    rm -rf "$XCFRAMEWORK_PATH"
    mkdir -p "$XCFRAMEWORK_DIR"

    # Create XCFramework
    xcodebuild -create-xcframework \
        -library "$DEVICE_LIB" \
        -headers "$GENERATED_DIR" \
        -library "$SIM_FAT_LIB" \
        -headers "$GENERATED_DIR" \
        -output "$XCFRAMEWORK_PATH"

    echo_step "Created XCFramework at $XCFRAMEWORK_PATH"
}

# Create module.modulemap for Swift imports
create_modulemap() {
    echo_step "Creating module map..."

    cat > "$GENERATED_DIR/module.modulemap" << 'EOF'
module vauchi_mobileFFI {
    header "vauchi_mobileFFI.h"
    export *
}
EOF
}

# Main build flow
main() {
    echo_step "Starting Vauchi iOS build..."
    echo "Project root: $PROJECT_ROOT"
    echo "iOS directory: $IOS_DIR"
    echo ""

    cd "$PROJECT_ROOT"

    check_prerequisites

    # Parse arguments
    case "${1:-all}" in
        device)
            build_device
            generate_bindings
            ;;
        simulator)
            build_simulator
            create_simulator_fat_lib
            generate_bindings
            ;;
        bindings)
            generate_bindings
            create_modulemap
            ;;
        xcframework)
            build_device
            build_simulator
            create_simulator_fat_lib
            generate_bindings
            create_modulemap
            create_xcframework
            ;;
        all|*)
            build_device
            build_simulator
            create_simulator_fat_lib
            generate_bindings
            create_modulemap
            create_xcframework
            ;;
    esac

    echo ""
    echo_step "Build complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Add VauchiMobile.xcframework to your Xcode project"
    echo "  2. Add Generated/vauchi_mobile.swift to your project"
    echo "  3. Set 'Library Search Paths' to include the framework"
    echo "  4. Import 'vauchi_mobile' in your Swift code"
}

main "$@"
