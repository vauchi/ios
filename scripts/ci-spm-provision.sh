#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared iOS CI SPM provisioning, used by build:debug AND build:release.
#
# Runs xcodegen, then provisions the vauchi-platform-swift FFI xcframework
# via a file:// SPM mirror so SwiftPM emits a `path:` binaryTarget and never
# reaches the `url:` URLSession download that hangs against Cloudflare-fronted
# gitlab.com for the 7-day timeoutIntervalForResource (= the 2h job timeout).
#
# REQUIRES the caller to export VAUCHI_PLATFORM_USE_LOCAL_XCFRAMEWORK=1 (set
# as a job variable) so the manifest takes the path: branch.
#
# Extracted verbatim from build:debug's former inline prelude (single source
# of truth). See _private problem 2026-04-26-vauchi-platform-swift-resolve-hang
# and 2026-06-28-ios-ci-spm-swift-syntax-checkout-hang.
set -euo pipefail

# Normalize SPM_ISOLATE_HOME if the caller provided one. CI sometimes passes a
# literal '$CI_PROJECT_DIR' reference that does not expand in the variables:
# section, or a relative path; xcodebuild needs an absolute HOME for its SPM
# config lookup. build:release intentionally leaves this unset so it keeps the
# shared config path for signing.
echo "  [debug] SPM_ISOLATE_HOME raw='${SPM_ISOLATE_HOME:-}' CI_PROJECT_DIR='${CI_PROJECT_DIR:-}' PWD='$PWD'"
if [ -n "${SPM_ISOLATE_HOME:-}" ]; then
  SPM_ISOLATE_HOME="${SPM_ISOLATE_HOME//\$CI_PROJECT_DIR/${CI_PROJECT_DIR:-$PWD}}"
  case "$SPM_ISOLATE_HOME" in
    /*) ;;
    *) SPM_ISOLATE_HOME="$PWD/$SPM_ISOLATE_HOME" ;;
  esac
  export SPM_ISOLATE_HOME
  echo "  [debug] SPM_ISOLATE_HOME normalized='$SPM_ISOLATE_HOME'"
else
  echo "  [debug] SPM_ISOLATE_HOME unset, will use shared config path"
fi

rm -rf Vauchi.xcodeproj
xcodegen generate
echo "── [$(date +%H:%M:%S)] SPM resolve (file:// mirror + env var) ──"
set -e

# 1. Determine version from project.yml (XcodeGen package pin).
V=$(sed -n '/vauchi-platform-swift/{n;s/.*"\([^"]*\)".*/\1/p;}' project.yml)
if [ -z "$V" ]; then
  echo "  ERROR: could not extract VauchiPlatform version from project.yml"
  exit 1
fi
echo "  Resolved version: $V"

# 2. Per-version mirror lives outside the build dir so it survives
# cache wipes and is shared across ios/macos jobs on this runner.
MIRROR="$HOME/.cache/vauchi-platform-swift-mirror/v$V"
# Bumped (-v5) on 2026-05-16 to align with macos's stamp ratchet
# (macos hit -v5 on 2026-05-04 for an orphaned-SHA cache poison
# that didn't trip ios; aligning so future invalidations bump both
# in lockstep — the shared `nell-shell` runner holds both caches).
# Prior bumps: v4 (gitlab eventual-consistency window after the
# v0.25.0 force-tag-move — first v3 rebuild ran before the new tag
# SHA propagated to all git replicas, so `git clone --branch
# v0.25.0` re-served the broken manifest and sanity checks 1+2
# didn't catch it because `let version` and the env-var switch
# survive intact in the broken Package.swift), v3 (force-moved
# v0.25.0 tag), v2 (symlink-fix invalidation). v5→v6:
# poisoned-mirror invalidation — the 600s lock-reclaim race let
# concurrent 0.51.30 bumps (ios!482 / macos!256) commit a torn
# xcframework that passed the old sanity and poisoned the shared
# cache; bumped in lockstep with macos (shared $MIRROR + stamp).
MIRROR_READY="$MIRROR/.ci-mirror-ready-v6"

# Concurrency guard for the runner-shared mirror: ios + macos jobs
# racing through the cache-miss path of the if/else below produced
# overlapping `rm -rf "$MIRROR" → git clone` invocations on
# 2026-05-16 (ios!426 + macos!225), surfacing as
# `could not lock config file: No such file or directory`. mkdir(1)
# is the POSIX-atomic primitive available on the runner without
# installing util-linux (macOS lacks flock(1)). Stale-lock timeout
# 600s = 6× empirical mirror-build time.
LOCKDIR="$HOME/.cache/vauchi-platform-swift-mirror/.lock-v$V"
mkdir -p "$(dirname "$LOCKDIR")"
LOCK_WAIT=0
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  if [ "$LOCK_WAIT" -ge 600 ]; then
    echo "  Mirror lock held >600s — treating as stale and reclaiming."
    rmdir "$LOCKDIR" 2>/dev/null || true
    continue
  fi
  echo "  Waiting for mirror lock at $LOCKDIR (${LOCK_WAIT}s)…"
  sleep 10
  LOCK_WAIT=$((LOCK_WAIT + 10))
done
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

# The iOS binary artifact the xcframework must contain. Used both to
# validate a cache-hit mirror (the guard below) and to fail-fast
# after a fresh build (Sanity check further down). A mirror can be
# stamped MIRROR_READY yet be missing this binary if a concurrent
# same-version bump job reclaimed the lock at the 600s stale
# threshold and tore the mirror mid-build — observed on macos!256
# racing ios!482, both bumping 0.51.30: `rm -rf "$MIRROR"` + re-clone
# of the upstream tag (which gitignores the xcframework) leaves a
# valid-version checkout with no binary, and SPM resolve fails
# "does not contain a binary artifact". The cache-hit guard treats a
# binary-less mirror as a miss and rebuilds, so a torn cache
# self-heals instead of failing every consumer that hits it.
BIN_PATH="VauchiPlatformFFI.xcframework/ios-arm64/VauchiPlatformFFI.framework/VauchiPlatformFFI"
if [ -f "$MIRROR_READY" ] && git -C "$MIRROR" cat-file -e "v$V:$BIN_PATH" 2>/dev/null; then
  echo "  Mirror cache hit at $MIRROR"
else
  if [ -f "$MIRROR_READY" ]; then
    echo "  Mirror cache STALE (xcframework binary missing) — rebuilding"
  fi
  echo "  Building mirror at $MIRROR"
  rm -rf "$MIRROR"
  mkdir -p "$(dirname "$MIRROR")"

  # Shallow clone of the upstream tag.
  git clone --quiet --depth=1 --branch "v$V" \
    https://gitlab.com/vauchi/vauchi-platform-swift.git "$MIRROR"

  # Sanity 1: tag's Package.swift declares matching version. Catches
  # the upstream release-CI bug observed for v0.21.8..v0.21.12 where
  # the bump commit forgot to update `let version = ...` — see
  # _private/docs/problems/2026-04-22-phantom-core-registry-artifacts/.
  PKG_VERSION=$(sed -n 's/^let version = "\([^"]*\)".*/\1/p' "$MIRROR/Package.swift")
  if [ "$PKG_VERSION" != "$V" ]; then
    echo "  ERROR: tag v$V Package.swift declares version=\"$PKG_VERSION\""
    exit 1
  fi

  # Sanity 2: env-var-aware binaryTarget present. Without Fix C,
  # the manifest unconditionally emits `url:` and SPM hangs.
  if ! grep -q 'VAUCHI_PLATFORM_USE_LOCAL_XCFRAMEWORK' "$MIRROR/Package.swift"; then
    echo "  ERROR: tag v$V Package.swift is missing the env-var switch."
    echo "  Bump core to a release that includes Fix C — see"
    echo "  _private/docs/problems/2026-04-26-vauchi-platform-swift-resolve-hang/."
    exit 1
  fi

  # Sanity 3: Package.swift actually parses. Catches the stale-tag
  # window after a force-tag-move where gitlab.com's git replicas
  # may briefly serve the pre-move SHA — e.g. v0.25.0 was moved
  # from e3a92e7 (broken ternary at line 28, mangled by old
  # swift-bindings-update regex) to 5cd0c24, and the first cache
  # rebuild caught the old SHA before propagation completed. Sanity
  # 1+2 don't catch this because both signal lines (`let version`
  # and `useLocalXCFramework`) survive intact in the broken file —
  # only the ternary body is mangled. `swift package dump-package`
  # is the same parser xcodebuild uses, so a green dump means SPM
  # resolve will not hit "Invalid manifest".
  if ! (cd "$MIRROR" && swift package dump-package > /dev/null 2>&1); then
    echo "  ERROR: tag v$V Package.swift fails to parse."
    echo "  This usually means gitlab.com's git replicas have not yet"
    echo "  propagated a recent force-tag-move. Wait 1–2 minutes and"
    echo "  re-trigger the pipeline; the next clone should pick up"
    echo "  the canonical tag SHA. The (broken) cache directory has"
    echo "  not been stamped MIRROR_READY, so the next run will"
    echo "  re-clone instead of cache-hit."
    rm -rf "$MIRROR"
    exit 1
  fi

  # Curl xcframework, place inside mirror (will be committed to
  # mirror tag). Public registry — no JOB-TOKEN needed.
  ZIP="/tmp/VauchiPlatformFFI-${CI_JOB_ID}-${V}.xcframework.zip"
  curl -fsSL --max-time 120 --retry 3 --retry-max-time 240 --retry-connrefused \
    "https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/generic/vauchi-platform/${V}/VauchiPlatformFFI.xcframework.zip" \
    -o "$ZIP"
  echo "  Downloaded $(du -h "$ZIP" | cut -f1)"
  unzip -o -q "$ZIP" -d "$MIRROR"
  rm -f "$ZIP"

  # Fix versioned-framework symlinks broken by upstream `zip -r`
  # (missing -y). The published xcframework stores macOS framework
  # symlinks (Versions/Current, Headers, Modules, Resources, and the
  # binary symlink) as plain 24–34-byte files containing the symlink
  # target text. SPM's `path:` binaryTarget validation checks that
  # the binary inside the framework is an actual binary; with the
  # broken form, resolve fails with "does not contain a binary
  # artifact". Mirrors the existing scripts/fix-xcframework-symlinks.sh
  # logic but applied to the mirror dir so the broken-symlink form
  # is never committed (and therefore never sees SPM resolve).
  # Remove this block once core publishes with `zip -ry` (see
  # core MR !259) and the bumped vauchi-platform-swift consumes it.
  for fw in "$MIRROR/VauchiPlatformFFI.xcframework"/macos-*/VauchiPlatformFFI.framework; do
    [ -d "$fw/Versions/A" ] || continue
    if [ -d "$fw/Versions/Current" ] && [ ! -L "$fw/Versions/Current" ]; then
      rm -rf "$fw/Versions/Current"
      (cd "$fw/Versions" && ln -sf A Current)
      for link in Headers Modules Resources; do
        if [ -e "$fw/$link" ] && [ ! -L "$fw/$link" ]; then
          rm -rf "$fw/$link"
        fi
        (cd "$fw" && ln -sf "Versions/Current/$link" "$link")
      done
      if [ -e "$fw/VauchiPlatformFFI" ] && [ ! -L "$fw/VauchiPlatformFFI" ]; then
        rm -f "$fw/VauchiPlatformFFI"
      fi
      (cd "$fw" && ln -sf "Versions/Current/VauchiPlatformFFI" "VauchiPlatformFFI")
    fi
  done

  # Commit + force-tag in the mirror so `git clone v$V` restores
  # the manifest AND the xcframework as one atomic checkout.
  # `-f` is required: VauchiPlatformFFI.xcframework/ is gitignored
  # upstream (it's a build output) — without -f, `git add` is a
  # silent no-op and the subsequent commit fails with "nothing to
  # commit, working tree clean".
  git -C "$MIRROR" add -f VauchiPlatformFFI.xcframework
  git -C "$MIRROR" -c user.email=ci@vauchi.local -c user.name=ci-mirror \
    commit -q -m "ci-mirror: bundle xcframework v$V"
  git -C "$MIRROR" tag -f "v$V"

  # Sanity: the commit must contain the iOS binary artifact path
  # ($BIN_PATH, defined above the cache-hit guard). If the binary is
  # missing (e.g. `git add -f` didn't recurse into the gitignored
  # dir, or the unzip failed silently), SPM resolve will fail with
  # "does not contain a binary artifact" — fail fast here instead.
  if ! git -C "$MIRROR" cat-file -e "v$V:$BIN_PATH" 2>/dev/null; then
    echo "  ERROR: mirror commit missing $BIN_PATH"
    echo "  Files captured in mirror commit:"
    git -C "$MIRROR" ls-tree -r "v$V" --name-only | grep VauchiPlatformFFI | head -20
    exit 1
  fi

  touch "$MIRROR_READY"
  echo "  Mirror built ($(du -sh "$MIRROR" | cut -f1), $(git -C "$MIRROR" ls-tree -r "v$V" --name-only | grep -c '^VauchiPlatformFFI.xcframework/') xcframework files)"
fi

# Release the mirror lock now: the critical section is the BUILD
# only. The EXIT-trap release (set at lock acquisition) is later
# OVERWRITTEN by the compile step's heartbeat/watchdog EXIT trap, so
# today the lock is effectively leaked until the next job's 600s
# stale-reclaim — which is why every concurrent same-version bump
# waits out 600s, reclaims the still-live lock, and collides in the
# build path, tearing the mirror and poisoning the shared cache
# (ios!482 / macos!256, 0.51.30). Freeing it explicitly here shrinks
# the critical section to the ~90s build; once READY-stamped the
# mirror is read-only for resolve, so concurrent jobs proceed in
# parallel against a stable dir.
rmdir "$LOCKDIR" 2>/dev/null || true
trap - EXIT

# 3. Wire SPM to the local mirror.
# Write mirror config to BOTH project-local AND user-level paths.
# Project-local works for raw `swift build`, but Xcode's SPM
# consults the user-level config (`~/Library/org.swift.swiftpm/
# configuration/mirrors.json`). On the runner, the trace
# `Fetching from https://gitlab.com/... (cached)` confirmed the
# project-local mirror was ignored.
MIRROR_JSON=$(printf '%s\n' \
  '{' \
  '  "version": 1,' \
  '  "object": [{' \
  '    "original": "https://gitlab.com/vauchi/vauchi-platform-swift.git",' \
  "    \"mirror\": \"file://$MIRROR\"" \
  '  }]' \
  '}')
mkdir -p .swiftpm/configuration
printf '%s' "$MIRROR_JSON" > .swiftpm/configuration/mirrors.json
# NOTE: the user-level config (~/Library/org.swift.swiftpm/...) that
# xcodebuild actually reads is now written under the shared host-wide
# config lock in §6, NOT here — §4/§5 run between this point and the
# resolve, leaving a window for a concurrent ios/macos bump pipeline to
# clobber it. Writing it adjacent to the resolve under .cfg-lock closes
# that window (matches macos!256).

# 4. Drop derived data + Xcode's shared module cache so the FFI
# swiftmodule is re-emitted from fresh C headers. Without this,
# newly-added types appear missing because Xcode reuses a
# swiftmodule compiled against the previous binding version.
rm -rf .derived-data
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# 5. On version delta, also wipe SPM's bare-mirror cache for
# vauchi-platform-swift so SPM re-fetches from the file:// mirror
# instead of using its cached gitlab.com refs (which would lack
# the locally-tagged commit). Other packages' caches are untouched.
# Also wipe the user-level Xcode SPM cache: the trace
# `Fetching from https://gitlab.com/... (cached)` proves Xcode's
# SPM was using a cached bare repo from a path OUTSIDE the
# project-local .spm-packages/ — likely the user-level cache that
# mirror config does not redirect cache lookups for.
rm -rf .spm-packages/repositories/vauchi-platform-swift-*
rm -rf .spm-packages/checkouts/vauchi-platform-swift
rm -rf .spm-packages/manifests/vauchi-platform-swift-*
rm -rf .spm-packages/artifacts/vauchi-platform-swift
rm -f  .spm-packages/workspace-state.json
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/vauchi-platform-swift-* 2>/dev/null || true
rm -rf ~/Library/org.swift.swiftpm/repositories/vauchi-platform-swift-* 2>/dev/null || true
rm -rf ~/Library/Developer/Xcode/DerivedData/Vauchi-*/SourcePackages 2>/dev/null || true
rm -f  Vauchi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
# SwiftPM TOFU fingerprint storage: when a tag is force-moved
# (v0.24.0 → Fix C, v0.25.0 → restored Package.swift), the
# recorded version→SHA mapping conflicts with the new SHA,
# producing "Revision X for ... version V does not match previously
# recorded value Y". The earlier wildcard `vauchi-platform-swift*`
# only matched URL-based identities; for the file:// mirror, SPM
# stores fingerprints under a hash of the path (e.g. `v0.25.0-<hex>/`)
# which the wildcard misses. Nuke the whole fingerprints dir —
# SPM re-trusts on next resolve, and the only consumer here is
# vauchi-platform-swift anyway.
rm -rf .spm-packages/security/fingerprints 2>/dev/null || true
rm -rf ~/.swiftpm/security/fingerprints 2>/dev/null || true
rm -rf ~/Library/org.swift.swiftpm/security/fingerprints 2>/dev/null || true
rm -rf ~/Library/Caches/org.swift.swiftpm/security/fingerprints 2>/dev/null || true

# 6. Write the user-level mirror config + resolve, under the
# host-wide config lock shared with macos.
#
# xcodebuild reads the *user-level*
# ~/Library/org.swift.swiftpm/configuration/mirrors.json. The shared
# file is clobbered by concurrent ios/macos bump pipelines (macos!248 /
# macos!249), so serialise the write→resolve window under a host-wide
# lock — no other pipeline can overwrite the config between our write
# and our resolve. macos writes the same file under the same .cfg-lock;
# the two ship together. mkdir(1) is the POSIX-atomic primitive (no
# flock on macOS). The section is just write+resolve (~1–2 min), so the
# 600s stale threshold never false-reclaims.
#
# build:debug passes SPM_ISOLATE_HOME and takes the isolated branch below: it
# writes the config into a JOB-PRIVATE HOME and resolves there — no shared
# ~/Library file, so no CFGLOCK and no cross-pipeline race
# (problem 2026-06-29-spm-mirror-config-race). The mirror itself ($MIRROR)
# stays at the shared real-HOME cache path the private config points to, so
# isolation costs zero extra mirror builds. The compile step that follows in
# build:debug MUST also run with HOME=$SPM_ISOLATE_HOME. build:release (signing,
# SPM_ISOLATE_HOME unset) falls through to the shared+CFGLOCK path below,
# UNCHANGED: it needs the real HOME for ~/Library/Keychains and is tag-only +
# barely raced, so single-writer contention on the shared config is fine.
echo "  [debug] about to choose branch, SPM_ISOLATE_HOME='${SPM_ISOLATE_HOME:-}'"
if [ -n "${SPM_ISOLATE_HOME:-}" ]; then
  echo "  [debug] taking isolated branch"
  CFG_DIR="$SPM_ISOLATE_HOME/Library/org.swift.swiftpm/configuration"
  mkdir -p "$CFG_DIR"
  printf '%s' "$MIRROR_JSON" > "$CFG_DIR/mirrors.json"
  echo "  [debug] wrote mirror config to $CFG_DIR/mirrors.json:"
  cat "$CFG_DIR/mirrors.json"
  echo ""
  echo "  [debug] running xcodebuild with HOME=$SPM_ISOLATE_HOME"
  HOME="$SPM_ISOLATE_HOME" xcodebuild -project Vauchi.xcodeproj -scheme Vauchi \
    -clonedSourcePackagesDirPath .spm-packages \
    -derivedDataPath .derived-data \
    -resolvePackageDependencies
  echo "  SPM resolve OK (private config $CFG_DIR — no shared file, no CFGLOCK)"
  exit 0
else
  echo "  [debug] taking shared branch"
fi

CFGLOCK="$HOME/.cache/vauchi-platform-swift-mirror/.cfg-lock"
mkdir -p "$(dirname "$CFGLOCK")"
CFG_WAIT=0
while ! mkdir "$CFGLOCK" 2>/dev/null; do
  if [ "$CFG_WAIT" -ge 600 ]; then
    echo "  Config lock held >600s — treating as stale and reclaiming."
    rmdir "$CFGLOCK" 2>/dev/null || true
    continue
  fi
  echo "  Waiting for config lock at $CFGLOCK (${CFG_WAIT}s)…"
  sleep 5
  CFG_WAIT=$((CFG_WAIT + 5))
done
trap 'rmdir "$CFGLOCK" 2>/dev/null || true' EXIT

mkdir -p ~/Library/org.swift.swiftpm/configuration
printf '%s' "$MIRROR_JSON" > ~/Library/org.swift.swiftpm/configuration/mirrors.json

# Resolve. Env var triggers `path:` binaryTarget; mirror has the
# xcframework. No URLSession download path is reachable.
xcodebuild -project Vauchi.xcodeproj -scheme Vauchi \
  -clonedSourcePackagesDirPath .spm-packages \
  -derivedDataPath .derived-data \
  -resolvePackageDependencies
echo "  SPM resolve OK (file:// mirror, no URLSession)"

# Resolve done — SPM cloned the mirror into project-local .spm-packages,
# so the user-level config is no longer needed. Release the lock.
rmdir "$CFGLOCK" 2>/dev/null || true
trap - EXIT
