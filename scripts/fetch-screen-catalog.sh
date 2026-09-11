#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fetches Core's screen catalog fixture into <out>. Falls back to the
# presentation contract fixture, cumulatively folded into one catalog
# entry per step, while the catalog has not landed on Core main — the
# render test then still exercises every screen the contract walks.
#
# Usage: fetch-screen-catalog.sh <out.json> [ref]
# Needs CI_JOB_TOKEN + CI_API_V4_URL (GitLab CI); locally, set
# VAUCHI_CORE_DIR to a checkout to read the fixtures from disk instead.
set -euo pipefail

out="${1:?usage: $0 <out.json> [ref]}"
ref="${2:-main}"
mkdir -p "$(dirname "$out")"

fetch() {
  local fixture="$1" dest="$2"
  if [ -n "${VAUCHI_CORE_DIR:-}" ]; then
    cp "$VAUCHI_CORE_DIR/vauchi-app/fixtures/$fixture" "$dest"
    return
  fi
  curl -fsSL -u "gitlab-ci-token:${CI_JOB_TOKEN}" \
    "${CI_API_V4_URL}/projects/vauchi%2Fcore/repository/files/vauchi-app%2Ffixtures%2F${fixture}/raw?ref=${ref}" \
    -o "$dest"
}

if fetch screen_catalog_v1.json "$out" 2>/dev/null && python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))['screens'] else 1)" "$out" 2>/dev/null; then
  echo "screen catalog source: screen_catalog_v1.json @ $ref"
  exit 0
fi

contract="$(dirname "$out")/presentation_contract_v1.json"
fetch presentation_contract_v1.json "$contract"
python3 - "$contract" "$out" <<'PY'
import json
import sys

contract = json.load(open(sys.argv[1], encoding="utf-8"))
batch = list(contract["initial_commands"])
screens = [{"code_id": "contract_initial", "title": "Contract: initial",
            "locale": "en", "commands": list(batch)}]
for index, step in enumerate(contract["steps"], 1):
    batch.extend(step["commands"])
    screens.append({"code_id": f"contract_step_{index}",
                    "title": f"Contract: step {index}", "locale": "en",
                    "commands": list(batch)})
json.dump({"schema_version": 1, "screens": screens}, open(sys.argv[2], "w", encoding="utf-8"))
print(f"screen catalog source: presentation_contract_v1.json @ {sys.argv[1]} folded into {len(screens)} screen(s)")
PY
