#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
[ "$#" -eq 1 ] || { echo "usage: $0 OUTPUT" >&2; exit 2; }
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
helper=$(mktemp)
trap 'rm -f "$helper"' EXIT
curl --fail-with-body --silent --show-error \
  --header "JOB-TOKEN: ${CI_JOB_TOKEN:-}" \
  "${CI_API_V4_URL:-https://gitlab.com/api/v4}/projects/vauchi%2Fcontract/repository/files/ci%2Ffetch-screen-catalog.py/raw?ref=5c8409f776e60bc6d0748d46a3a4c93c08516a9d" \
  -o "$helper"
python3 "$helper" "$1" --repo "$repo_dir"
