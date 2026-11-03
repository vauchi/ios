#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
[ "$#" -eq 1 ] || { echo "usage: $0 OUTPUT" >&2; exit 2; }
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
helper="$scratch/fetch-screen-catalog.py"
python=python3
if ! python3 -c 'import tomllib' 2>/dev/null; then
  python3 -m venv "$scratch/venv"
  python="$scratch/venv/bin/python"
  "$python" -m pip install --disable-pip-version-check 'tomli==2.2.1'
fi
curl --fail-with-body --silent --show-error \
  --header "JOB-TOKEN: ${CI_JOB_TOKEN:-}" \
  "${CI_API_V4_URL:-https://gitlab.com/api/v4}/projects/vauchi%2Fcontract/repository/files/ci%2Ffetch-screen-catalog.py/raw?ref=5ff7c6fe7240a69c2a5b901f5f62745ee5626b5a" \
  -o "$helper"
"$python" "$helper" "$1" --repo "$repo_dir"
