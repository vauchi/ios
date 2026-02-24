#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Setup code signing for CI builds.
# Creates a temporary keychain, imports the distribution certificate,
# and writes the App Store Connect API key to disk.
#
# Required CI variables:
#   IOS_DIST_CERT          - Base64-encoded .p12 distribution certificate
#   IOS_DIST_CERT_PASSWORD - Password for the .p12 certificate
#   ASC_KEY_ID             - App Store Connect API Key ID
#   ASC_ISSUER_ID          - App Store Connect Issuer ID
#   ASC_KEY_CONTENT        - Base64-encoded .p8 API key file

set -euo pipefail

# Validate required CI variables
for var in IOS_DIST_CERT IOS_DIST_CERT_PASSWORD ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_CONTENT; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required CI variable $var is not set"
        exit 1
    fi
done

KEYCHAIN_NAME="ci-signing.keychain-db"
KEYCHAIN_PASSWORD=$(head -c 32 /dev/urandom | base64)

echo "--- Setting up code signing ---"

# Create temporary keychain
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 3600 "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

# Add to search list (so xcodebuild can find certs)
security list-keychains -d user -s "$KEYCHAIN_NAME" $(security list-keychains -d user | tr -d '"')

# Import distribution certificate
CERT_PATH=$(mktemp /tmp/cert.XXXXXX.p12)
chmod 600 "$CERT_PATH"
echo "$IOS_DIST_CERT" | base64 --decode > "$CERT_PATH"
security import "$CERT_PATH" \
    -k "$KEYCHAIN_NAME" \
    -P "$IOS_DIST_CERT_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
rm -f "$CERT_PATH"

# Allow codesign to access keychain without prompt
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

# Write App Store Connect API key to disk
# xcrun altool looks for keys in ./private_keys/
mkdir -p private_keys
echo "$ASC_KEY_CONTENT" | base64 --decode > "private_keys/AuthKey_${ASC_KEY_ID}.p8"

echo "--- Code signing setup complete ---"
echo "Keychain: $KEYCHAIN_NAME"
echo "API Key: private_keys/AuthKey_${ASC_KEY_ID}.p8"
