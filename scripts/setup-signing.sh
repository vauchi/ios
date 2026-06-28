#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Setup code signing for CI builds.
# Creates a temporary keychain, imports the distribution certificate,
# and writes the App Store Connect API key to disk.
#
# Required CI variables:
#   APPLE_DIST_CERT          - Base64-encoded .p12 distribution certificate
#   APPLE_DIST_CERT_PASSWORD - Password for the .p12 certificate
#   ASC_KEY_ID             - App Store Connect API Key ID
#   ASC_ISSUER_ID          - App Store Connect Issuer ID
#   ASC_KEY_CONTENT        - Base64-encoded .p8 API key file

set -euo pipefail

# Validate required CI variables
for var in APPLE_DIST_CERT APPLE_DIST_CERT_PASSWORD ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_CONTENT APP_STORE_PROFILE_IOS; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required CI variable $var is not set"
        exit 1
    fi
done

KEYCHAIN_NAME="ci-signing.keychain-db"
KEYCHAIN_PASSWORD=$(head -c 32 /dev/urandom | base64)

echo "--- Setting up code signing ---"

# Create temporary keychain. Delete any stale one first: a prior run that
# died between create-keychain and teardown leaves it on disk, and a keychain
# that's on disk but not in the search list is not removed by teardown, so a
# plain create-keychain then fails with "already exists".
security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 3600 "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

# Add to search list (so xcodebuild can find certs)
security list-keychains -d user -s "$KEYCHAIN_NAME" $(security list-keychains -d user | tr -d '"')

# Import distribution certificate. Use a temp dir for the .p12: BSD mktemp
# (the macOS runner) requires the Xs to be trailing, so a
# "cert.XXXXXX.p12" template yields a non-random, colliding name and fails
# with "File exists" once a prior run has leaked one.
CERT_DIR=$(mktemp -d)
CERT_PATH="$CERT_DIR/cert.p12"
echo "$APPLE_DIST_CERT" | base64 --decode > "$CERT_PATH"
chmod 600 "$CERT_PATH"
security import "$CERT_PATH" \
    -k "$KEYCHAIN_NAME" \
    -P "$APPLE_DIST_CERT_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
rm -rf "$CERT_DIR"

# Allow codesign to access keychain without prompt
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

# Write App Store Connect API key to disk
# xcrun altool looks for keys in ./private_keys/
mkdir -p private_keys
echo "$ASC_KEY_CONTENT" | base64 --decode > "private_keys/AuthKey_${ASC_KEY_ID}.p8"

# Install the App Store provisioning profile so the archive/export can sign
# MANUALLY — this removes the -allowProvisioningUpdates network call to Apple
# that was hanging the archive for the full 2h job timeout. Xcode locates
# profiles by <UUID>.mobileprovision in this directory.
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
PROFILE_WORK=$(mktemp -d)
echo "$APP_STORE_PROFILE_IOS" | base64 --decode > "$PROFILE_WORK/p.mobileprovision"
PROFILE_UUID=$(security cms -D -i "$PROFILE_WORK/p.mobileprovision" | plutil -extract UUID raw -)
cp "$PROFILE_WORK/p.mobileprovision" "$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
rm -rf "$PROFILE_WORK"
echo "Installed provisioning profile: $PROFILE_UUID"

echo "--- Code signing setup complete ---"
echo "Keychain: $KEYCHAIN_NAME"
echo "API Key: private_keys/AuthKey_${ASC_KEY_ID}.p8"
