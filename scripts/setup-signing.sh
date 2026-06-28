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

# Add to search list (so xcodebuild can find certs). Word-splitting the
# existing keychain list into separate args is intentional.
# shellcheck disable=SC2046
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
security cms -D -i "$PROFILE_WORK/p.mobileprovision" -o "$PROFILE_WORK/p.plist"
PROFILE_UUID=$(plutil -extract UUID raw -o - "$PROFILE_WORK/p.plist")
cp "$PROFILE_WORK/p.mobileprovision" "$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
echo "Installed provisioning profile: $PROFILE_UUID"

# ---- Auto-pin the signing identity ----------------------------------------
# A .p12 can bundle several certs (dev, Developer ID, multiple Apple
# Distribution — some revoked/expired). Signing by the generic name
# "Apple Distribution" then binds to an arbitrary, possibly revoked cert: a
# 6-identity bundle once bound to a revoked serial and burned a release. Pin
# to the one identity that is BOTH valid (security's -v policy drops
# revoked/expired) AND authorized by the provisioning profile, and fail fast
# (here, in seconds) instead of 1 min into a cryptic archive error.
echo "--- Imported code-signing identities (all) ---"
security find-identity -p codesigning "$KEYCHAIN_NAME" || true
echo "--- Valid (non-revoked, unexpired) identities ---"
security find-identity -v -p codesigning "$KEYCHAIN_NAME" || true

# SHA-1 hashes (uppercase, no separators) of VALID Apple Distribution identities.
valid_hashes=$(security find-identity -v -p codesigning "$KEYCHAIN_NAME" \
    | grep "Apple Distribution" \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]+).*/\1/' \
    | tr 'a-f' 'A-F' | sort -u)
if [ -z "$valid_hashes" ]; then
    echo "ERROR: imported .p12 has no VALID 'Apple Distribution' identity"
    echo "       (all revoked/expired — see lists above). Export a current,"
    echo "       single Apple Distribution cert and update APPLE_DIST_CERT."
    exit 1
fi

# SHA-1 fingerprints the provisioning profile authorizes (DeveloperCertificates).
profile_hashes=$(plutil -extract DeveloperCertificates xml1 -o - "$PROFILE_WORK/p.plist" 2>/dev/null \
    | grep -oE '<data>[^<]+</data>' | sed -E 's#</?data>##g' \
    | while IFS= read -r b64; do
        printf '%s' "$b64" | base64 --decode 2>/dev/null \
            | openssl x509 -inform DER -noout -fingerprint -sha1 2>/dev/null \
            | sed -E 's/^.*=//; s/://g'
      done | tr 'a-f' 'A-F' | sort -u)
rm -rf "$PROFILE_WORK"

# Prefer the identity that is valid AND profile-authorized.
sign_hash=""
while IFS= read -r h; do
    [ -n "$h" ] || continue
    if printf '%s\n' "$profile_hashes" | grep -qx "$h"; then
        sign_hash="$h"
        break
    fi
done <<VALID
$valid_hashes
VALID

if [ -z "$sign_hash" ]; then
    if [ "$(printf '%s\n' "$valid_hashes" | grep -c .)" -eq 1 ]; then
        sign_hash="$valid_hashes"
        echo "WARNING: no valid identity matched the profile's authorized certs;"
        echo "         using the only valid Apple Distribution identity. If export"
        echo "         fails, regenerate 'Vauchi iOS App Store' for this cert."
    else
        vh=$(printf '%s' "$valid_hashes" | tr '\n' ' ')
        ph=$(printf '%s' "$profile_hashes" | tr '\n' ' ')
        echo "ERROR: the profile authorizes none of the valid Apple Distribution"
        echo "       identities, and there is more than one valid candidate:"
        echo "         valid:          $vh"
        echo "         profile-allows: ${ph:-(none parsed)}"
        echo "       Regenerate 'Vauchi iOS App Store' for the intended cert."
        exit 1
    fi
fi

echo "Pinned signing identity: $sign_hash"
printf '%s\n' "$sign_hash" > "${CI_PROJECT_DIR:-$PWD}/.signing-identity"

# Pin the export step too: ExportOptions.plist's signingCertificate accepts a
# SHA-1 hash. CI re-clones per job, so this in-place edit never persists to git.
if [ -f ExportOptions.plist ]; then
    plutil -replace signingCertificate -string "$sign_hash" ExportOptions.plist
    echo "Pinned ExportOptions.plist signingCertificate -> $sign_hash"
fi

echo "--- Code signing setup complete ---"
echo "Keychain: $KEYCHAIN_NAME"
echo "API Key: private_keys/AuthKey_${ASC_KEY_ID}.p8"
