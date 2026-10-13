#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# fetch-wwdr-g3.sh hands setup-signing.sh the Apple WWDR G3 intermediate,
# without which the runner reports "0 valid identities" for a good
# distribution certificate (vauchi/private#665). It must accept only the
# pinned certificate.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fetch="$here/../fetch-wwdr-g3.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Not Apple WWDR" \
    -keyout "$work/impostor.key" -outform DER -out "$work/impostor.cer" 2>/dev/null

if WWDR_G3_URL="file://$work/impostor.cer" "$fetch" "$work/impostor-out.cer" >/dev/null 2>&1; then
    fail "a certificate with another fingerprint is accepted"
fi
[ ! -e "$work/impostor-out.cer" ] || fail "a rejected certificate is left on disk"

if WWDR_G3_URL="file://$work/missing.cer" "$fetch" "$work/missing-out.cer" >/dev/null 2>&1; then
    fail "a failed download is accepted"
fi

if "$fetch" "$work/g3.cer"; then
    subject=$(openssl x509 -inform DER -in "$work/g3.cer" -noout -subject)
    case "$subject" in
        *"Apple Worldwide Developer Relations Certification Authority"*) ;;
        *) fail "the fetched certificate is not Apple WWDR: $subject" ;;
    esac
    case "$subject" in
        *"OU = G3"* | *"OU=G3"*) ;;
        *) fail "the fetched certificate is not the G3 generation: $subject" ;;
    esac
else
    fail "Apple's own G3 certificate is refused"
fi

if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "fetch-wwdr-g3: all checks passed"
