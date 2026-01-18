#!/bin/bash
#
# Vauchi iOS Development Setup Script
#
# This script sets up Xcode and iOS development environment for new developers.
# Run this after installing Xcode from the App Store or developer.apple.com.
#
# Usage: ./scripts/setup-xcode.sh
#

set -e

echo "=== Vauchi iOS Development Setup ==="
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "ERROR: Xcode is not installed."
    echo ""
    echo "Install Xcode using one of these methods:"
    echo ""
    echo "1. App Store (easiest):"
    echo "   Open App Store and search for 'Xcode'"
    echo ""
    echo "2. Developer Portal (for specific versions):"
    echo "   a. Go to https://developer.apple.com/download/all/"
    echo "   b. Sign in with your Apple ID"
    echo "   c. Download the Xcode .xip file"
    echo "   d. Double-click to extract, then move Xcode.app to /Applications"
    echo ""
    echo "After installing, run this script again."
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -1)
echo "Found: $XCODE_VERSION"
echo ""

# Step 1: Accept Xcode license
echo "Step 1: Checking Xcode license agreement..."
if ! xcodebuild -license check &> /dev/null; then
    echo "You need to accept the Xcode license agreement."
    echo "Running: sudo xcodebuild -license accept"
    echo ""
    sudo xcodebuild -license accept
    echo "License accepted."
else
    echo "License already accepted."
fi
echo ""

# Step 2: Run first launch setup
echo "Step 2: Running Xcode first launch setup..."
echo "This installs required components (may take a few minutes)..."
xcodebuild -runFirstLaunch
echo "First launch setup complete."
echo ""

# Step 3: Check for iOS platform
echo "Step 3: Checking for iOS platform..."
if xcrun simctl list devices 2>/dev/null | grep -q "iPhone"; then
    echo "iOS Simulator devices found."
else
    echo "No iOS Simulator devices found."
    echo ""
    echo "Installing iOS platform (this may take a while)..."
    echo "Running: xcodebuild -downloadPlatform iOS"
    echo ""
    xcodebuild -downloadPlatform iOS
    echo ""
    echo "iOS platform installed."
fi
echo ""

# Step 4: Verify setup
echo "Step 4: Verifying setup..."
echo ""
echo "Xcode path:"
xcode-select -p
echo ""
echo "Available simulators:"
xcrun simctl list devices available | head -20
echo ""

# Step 5: Check Rust iOS targets (optional for UniFFI builds)
echo "Step 5: Checking Rust iOS targets..."
if command -v rustup &> /dev/null; then
    if rustup target list --installed | grep -q "aarch64-apple-ios"; then
        echo "Rust iOS targets installed."
    else
        echo "Installing Rust iOS targets..."
        rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
        echo "Rust iOS targets installed."
    fi
else
    echo "Rust not found. Install from https://rustup.rs if you need to build UniFFI bindings."
fi
echo ""

echo "=== Setup Complete ==="
echo ""
echo "You can now build the iOS app:"
echo "  cd vauchi-ios"
echo "  xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 16' build"
echo ""
echo "Or open in Xcode:"
echo "  open Vauchi.xcodeproj"
echo ""
