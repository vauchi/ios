#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Per-job SwiftPM mirror-config isolation for the iOS *test* jobs.
#
# The test jobs (test:unit / test:snapshots / test:ui) reuse build:debug's
# resolved .spm-packages, but xcodebuild re-validates the package graph
# against the USER-LEVEL mirror config at
# ~/Library/org.swift.swiftpm/configuration/mirrors.json. That single file
# is shared by every ios + macos pipeline on the one Mac runner, so a
# concurrent macos bump at a different version clobbers it mid-build and the
# test resolve fails "Could not resolve package dependencies" (it reads the
# OTHER repo's version). See _private problem 2026-06-29-spm-mirror-config-race.
#
# Fix: write the correct-version config into a JOB-PRIVATE HOME
# ($CI_PROJECT_DIR/.spm-home) and have the caller run xcodebuild with
# HOME pointed there. No shared file is read -> no race, regardless of how
# fast core churns versions. The mirror itself stays shared (absolute
# file:// path, version-specific dir, read-only for resolve -> no clobbering),
# so ONLY the config is isolated; zero extra mirror builds.
#
# Not applied to signing jobs (build:release / deploy:testflight): they need
# ~/Library/Keychains + provisioning profiles, which a private HOME would
# hide, and they are tag-triggered + barely raced.
#
# $HOME here is the REAL runner home: the caller overrides HOME only on the
# xcodebuild command, not for this script, so the mirror path below resolves
# against the cache build:debug populated. The simulator is unaffected — its
# device set comes from launchd's CoreSimulator service (real HOME), not the
# xcodebuild client's HOME.
set -euo pipefail

V=$(sed -n '/vauchi-platform-swift/{n;s/.*"\([^"]*\)".*/\1/p;}' project.yml)
[ -n "$V" ] || { echo "  ERROR: no VauchiPlatform version in project.yml"; exit 1; }

ZIPFILE="$HOME/.cache/vauchi-platform-zips/v$V.zip"
if [ ! -f "$ZIPFILE" ]; then
  echo "  ERROR: cached XCFramework zip $ZIPFILE missing — build:debug should have downloaded it."
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  ZSHA=$(sha256sum "$ZIPFILE" | cut -c1-12)
else
  ZSHA=$(shasum -a 256 "$ZIPFILE" | cut -c1-12)
fi
MIRROR="$HOME/.cache/vauchi-platform-swift-mirror/v$V-$ZSHA"
if [ ! -d "$MIRROR" ]; then
  echo "  ERROR: mirror $MIRROR missing — build:debug should have built it."
  exit 1
fi

CFG_DIR="$CI_PROJECT_DIR/.spm-home/Library/org.swift.swiftpm/configuration"
mkdir -p "$CFG_DIR"
printf '%s' "$(printf '%s\n' \
  '{' \
  '  "version": 1,' \
  '  "object": [{' \
  '    "original": "https://gitlab.com/vauchi/vauchi-platform-swift.git",' \
  "    \"mirror\": \"file://$MIRROR\"" \
  '  }]' \
  '}')" > "$CFG_DIR/mirrors.json"
echo "  per-job SPM config: v$V -> file://$MIRROR (HOME=$CI_PROJECT_DIR/.spm-home)"
