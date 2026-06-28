#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Teardown code signing after CI build.
# Removes the temporary keychain and API key files.

set -uo pipefail  # No -e: best-effort cleanup

KEYCHAIN_NAME="ci-signing.keychain-db"

echo "--- Tearing down code signing ---"

# Delete temporary keychain unconditionally by name. Gating on the search
# list misses a keychain that exists on disk but was never added to (or was
# dropped from) the list, leaking it to the next run's create-keychain.
if security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null; then
    echo "Deleted keychain: $KEYCHAIN_NAME"
fi

# Remove API key files
rm -rf private_keys/
echo "Removed API key files"

echo "--- Teardown complete ---"
