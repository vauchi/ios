#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Teardown code signing after CI build.
# Removes the temporary keychain and API key files.

set -uo pipefail  # No -e: best-effort cleanup

KEYCHAIN_NAME="ci-signing.keychain-db"

echo "--- Tearing down code signing ---"

# Delete temporary keychain
if security list-keychains -d user | grep -q "$KEYCHAIN_NAME"; then
    security delete-keychain "$KEYCHAIN_NAME"
    echo "Deleted keychain: $KEYCHAIN_NAME"
fi

# Remove API key files
rm -rf private_keys/
echo "Removed API key files"

echo "--- Teardown complete ---"
