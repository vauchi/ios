#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Download Apple's WWDR G3 intermediate to <dest>, refusing any other
# certificate. Usage: fetch-wwdr-g3.sh <dest>
#
# The distribution certificate chains through G3, and security find-identity
# calls an identity invalid when the chain is incomplete. setup-signing.sh
# imports this into its keychain so signing does not depend on what the
# runner host has installed (vauchi/private#665).

set -euo pipefail

WWDR_G3_SHA1=06EC06599F4ED0027CC58956B4D3AC1255114F35
url=${WWDR_G3_URL:-https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer}
dest=${1:?usage: fetch-wwdr-g3.sh <dest>}

if ! curl -sSL --fail-with-body --retry 3 -o "$dest" "$url"; then
    rm -f "$dest"
    echo "ERROR: could not download the Apple WWDR G3 intermediate from $url" >&2
    exit 1
fi

actual=$(openssl x509 -inform DER -in "$dest" -noout -fingerprint -sha1 2>/dev/null \
    | sed -E 's/^.*=//; s/://g' | tr 'a-f' 'A-F' || true)
if [ "$actual" != "$WWDR_G3_SHA1" ]; then
    rm -f "$dest"
    echo "ERROR: $url is not the Apple WWDR G3 intermediate" >&2
    echo "       expected SHA-1 $WWDR_G3_SHA1, got ${actual:-(not a DER certificate)}" >&2
    exit 1
fi
echo "Apple WWDR G3 intermediate verified ($WWDR_G3_SHA1)"
