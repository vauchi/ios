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

# 2. Content-addressed mirror (2026-07-31,
#    _private/docs/problems/2026-07-31-spm-mirror-orphaned-pins).
#
# The mirror directory name binds the exact xcframework bytes it
# holds: v$V-<zip sha256 prefix>. A completed mirror is NEVER modified
# or deleted in place — rebuilds build a sibling tmp dir and publish
# with an atomic mv — so an SPM pin (workspace-state.json, CI-cached
# .spm-packages) can never reference a destroyed commit. This retires
# the force-tag orphan class (v0.25.0, daab1b91, 08b68bd) and the
# torn-read race (readers hold no lock; the old code rm -rf'd the
# live path). Deletion happens only via the age-based GC at the
# bottom of this section.
#
# Stamp v7 (lockstep with macos, shared runner): v6→v7 invalidates
# all pre-content-addressing mirrors, whose pins may reference
# already-orphaned commits. Prior bumps: v6 (torn 0.51.30 mirror),
# v5/v4/v3/v2 — see git history for the archaeology.

MIRROR_BASE="$HOME/.cache/vauchi-platform-swift-mirror"
ZIPSTORE="$HOME/.cache/vauchi-platform-zips"
ZIPFILE="$ZIPSTORE/v$V.zip"
mkdir -p "$MIRROR_BASE" "$ZIPSTORE"

# Persistent zip store: the content hash names the mirror, so the zip
# is needed on every run. Cached zips are self-validating — a corrupt
# or stale file simply hashes to a fresh mirror path, and is deleted
# if it fails to unzip so the next run re-downloads.
# Portable SHA-256 (GNU/BusyBox have sha256sum, macOS has shasum).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -c1-12
  else
    shasum -a 256 "$1" | cut -c1-12
  fi
}

if [ ! -f "$ZIPFILE" ]; then
  curl -fsSL --max-time 120 --retry 3 --retry-max-time 240 --retry-connrefused \
    "https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/generic/vauchi-platform/${V}/VauchiPlatformFFI.xcframework.zip" \
    -o "$ZIPFILE.tmp.$$"
  mv "$ZIPFILE.tmp.$$" "$ZIPFILE"
fi
ZSHA=$(sha256_of "$ZIPFILE")
MIRROR="$MIRROR_BASE/v$V-$ZSHA"
MIRROR_READY="$MIRROR/.ci-mirror-ready-v7"
LOCKDIR="$MIRROR_BASE/.lock-v$V-$ZSHA"
echo "  Mirror content key: v$V-$ZSHA"

# mkdir(1) lock — POSIX-atomic (macOS lacks flock). Guards BUILD and
# PUBLISH of this content path only; readers never take it because a
# published mirror is immutable. Stale-lock timeout 600s = 6×
# empirical mirror-build time; a false reclaim now costs a duplicate
# tmp build, not a torn mirror — the publish step refuses to replace
# an existing dir, so the loser validates and adopts the winner's.
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

# The iOS binary artifact the xcframework must contain, checked by
# the cache-hit guard and the post-build sanity. A torn mirror (e.g.
# interrupted clone/unzip) fails the guard and is moved aside — never
# deleted in place — then rebuilt fresh.
BIN_PATH="VauchiPlatformFFI.xcframework/ios-arm64/VauchiPlatformFFI.framework/VauchiPlatformFFI"

mirror_tag_sha() {
  git -C "$MIRROR" rev-parse "v$V^{commit}" 2>/dev/null || printf ''
}

# Cache-hit requires the full chain: stamp present, stamp's recorded
# SHA == the tag's current SHA (a mismatch means the tag moved under
# us — orphan), binary present. Each failure mode logs its own name
# so recurrences are attributable from the job log alone.
if [ -f "$MIRROR_READY" ] \
  && [ "$(cat "$MIRROR_READY")" = "$(mirror_tag_sha)" ] \
  && git -C "$MIRROR" cat-file -e "v$V:$BIN_PATH" 2>/dev/null; then
  echo "  Mirror cache hit at $MIRROR (sha $(cat "$MIRROR_READY"))"
else
  if [ ! -d "$MIRROR" ]; then
    echo "  No mirror for v$V-$ZSHA — fresh build"
  elif [ ! -d "$MIRROR/.git" ]; then
    echo "  Mirror TORN (no .git — interrupted clone) — rebuilding"
  elif [ ! -f "$MIRROR_READY" ]; then
    echo "  Mirror TORN (no ready stamp — interrupted build) — rebuilding"
  elif [ "$(cat "$MIRROR_READY")" != "$(mirror_tag_sha)" ]; then
    echo "  Mirror ORPHANED/MOVED (tag sha '$(mirror_tag_sha)' != stamp '$(cat "$MIRROR_READY")') — rebuilding"
  else
    echo "  Mirror TORN (xcframework binary missing) — rebuilding"
  fi
  # Never delete a possibly-read path: move it aside; the GC below
  # reaps .torn dirs on later runs.
  if [ -d "$MIRROR" ]; then
    mv "$MIRROR" "$MIRROR.torn.$$"
  fi

  TMP_MIRROR="$MIRROR.tmp.$$"
  echo "  Building mirror at $TMP_MIRROR"

  # Shallow clone of the upstream tag.
  git clone --quiet --depth=1 --branch "v$V" \
    https://gitlab.com/vauchi/vauchi-platform-swift.git "$TMP_MIRROR"

  # Sanity 1: tag's Package.swift declares matching version. Catches
  # the upstream release-CI bug observed for v0.21.8..v0.21.12 where
  # the bump commit forgot to update `let version = ...` — see
  # _private/docs/problems/2026-04-22-phantom-core-registry-artifacts/.
  PKG_VERSION=$(sed -n 's/^let version = "\([^"]*\)".*/\1/p' "$TMP_MIRROR/Package.swift")
  if [ "$PKG_VERSION" != "$V" ]; then
    echo "  ERROR: tag v$V Package.swift declares version=\"$PKG_VERSION\""
    rm -rf "$TMP_MIRROR"
    exit 1
  fi

  # Sanity 2: env-var-aware binaryTarget present. Without Fix C,
  # the manifest unconditionally emits `url:` and SPM hangs.
  if ! grep -q 'VAUCHI_PLATFORM_USE_LOCAL_XCFRAMEWORK' "$TMP_MIRROR/Package.swift"; then
    echo "  ERROR: tag v$V Package.swift is missing the env-var switch."
    echo "  Bump core to a release that includes Fix C — see"
    echo "  _private/docs/problems/2026-04-26-vauchi-platform-swift-resolve-hang/."
    rm -rf "$TMP_MIRROR"
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
  # resolve will not hit "Invalid manifest". The tmp dir is never
  # published, so the next run re-clones instead of cache-hitting.
  if ! (cd "$TMP_MIRROR" && swift package dump-package > /dev/null 2>&1); then
    echo "  ERROR: tag v$V Package.swift fails to parse."
    echo "  This usually means gitlab.com's git replicas have not yet"
    echo "  propagated a recent force-tag-move. Wait 1–2 minutes and"
    echo "  re-trigger the pipeline; the next clone should pick up"
    echo "  the canonical tag SHA."
    rm -rf "$TMP_MIRROR"
    exit 1
  fi

  # Unzip the cached xcframework into the mirror (committed to the
  # mirror tag below). A corrupt cached zip poisons the hash-named
  # path permanently if left in the store — delete it so the next
  # run re-downloads.
  if ! unzip -o -q "$ZIPFILE" -d "$TMP_MIRROR"; then
    echo "  ERROR: cached zip $ZIPFILE failed to unzip — deleting it."
    rm -f "$ZIPFILE"
    rm -rf "$TMP_MIRROR"
    exit 1
  fi

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
  for fw in "$TMP_MIRROR/VauchiPlatformFFI.xcframework"/macos-*/VauchiPlatformFFI.framework; do
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

  # Commit + tag inside the tmp mirror so the published dir restores
  # the manifest AND the xcframework as one atomic checkout.
  # `-f` is required: VauchiPlatformFFI.xcframework/ is gitignored
  # upstream (it's a build output) — without -f, `git add` is a
  # silent no-op and the subsequent commit fails with "nothing to
  # commit, working tree clean". The -f tag move happens only inside
  # the unpublished tmp dir (moving the clone's tag onto the new
  # commit) — never under a reader.
  git -C "$TMP_MIRROR" add -f VauchiPlatformFFI.xcframework
  git -C "$TMP_MIRROR" -c user.email=ci@vauchi.local -c user.name=ci-mirror \
    commit -q -m "ci-mirror: bundle xcframework v$V ($ZSHA)"
  git -C "$TMP_MIRROR" tag -f "v$V"

  # Sanity: the commit must contain the iOS binary artifact path
  # ($BIN_PATH, defined above the cache-hit guard). If the binary is
  # missing (e.g. `git add -f` didn't recurse into the gitignored
  # dir, or the unzip failed silently), SPM resolve will fail with
  # "does not contain a binary artifact" — fail fast here instead.
  if ! git -C "$TMP_MIRROR" cat-file -e "v$V:$BIN_PATH" 2>/dev/null; then
    echo "  ERROR: mirror commit missing $BIN_PATH"
    echo "  Files captured in mirror commit:"
    git -C "$TMP_MIRROR" ls-tree -r "v$V" --name-only | grep VauchiPlatformFFI | head -20
    rm -rf "$TMP_MIRROR"
    exit 1
  fi

  # SHA-in-stamp: the ready stamp records the exact commit the tag
  # resolves to, so a later tag move fails the guard loud (named
  # ORPHANED/MOVED diagnostic) instead of surfacing as an SPM
  # "unable to read tree" mystery.
  git -C "$TMP_MIRROR" rev-parse "v$V^{commit}" > "$TMP_MIRROR/.ci-mirror-ready-v7"

  # Atomic publish. If a false-reclaimed lock let a twin publish
  # first, the mv would nest instead of replace — so check, then
  # validate and adopt the winner's dir (same content key, so its
  # content is by definition what we built).
  if [ -d "$MIRROR" ]; then
    echo "  Twin published $MIRROR first — validating and adopting it"
    rm -rf "$TMP_MIRROR"
    if [ ! -f "$MIRROR_READY" ] \
      || [ "$(cat "$MIRROR_READY")" != "$(mirror_tag_sha)" ]; then
      echo "  ERROR: twin mirror at $MIRROR fails the stamp guard"
      exit 1
    fi
  else
    mv "$TMP_MIRROR" "$MIRROR"
    echo "  Mirror published at $MIRROR"
  fi
  echo "  Mirror ready ($(du -sh "$MIRROR" | cut -f1), $(git -C "$MIRROR" ls-tree -r "v$V" --name-only | grep -c '^VauchiPlatformFFI.xcframework/') xcframework files, sha $(cat "$MIRROR_READY"))"
fi

# Release the lock: it guards build+publish only. A stamped mirror is
# immutable, so concurrent readers proceed in parallel against a
# stable dir. (History: the EXIT-trap release used to be overwritten
# by the compile step's trap, leaking the lock into the next job's
# 600s stale-reclaim — ios!482 / macos!256.)
rmdir "$LOCKDIR" 2>/dev/null || true
trap - EXIT

# GC: the only deletion of mirror dirs. Age out published mirrors
# (30-day horizon — far beyond any CI-cache revival window) and reap
# torn/tmp leftovers, but never the current job's path and never a
# path with a live build lock. -prune+-mtime is the portable form
# (GNU/BSD/BusyBox).
for d in "$MIRROR_BASE"/v*; do
  [ -d "$d" ] || continue
  [ "$d" = "$MIRROR" ] && continue
  base=$(basename "$d")
  case "$base" in
    *.torn.*)
      rm -rf "$d"
      ;;
    *.tmp.*)
      stem=${base%%.tmp.*}
      [ -d "$MIRROR_BASE/.lock-$stem" ] || rm -rf "$d"
      ;;
    *)
      [ -d "$MIRROR_BASE/.lock-$base" ] && continue
      if [ -n "$(find "$d" -prune -mtime +30 -print 2>/dev/null)" ]; then
        echo "  GC: reaping mirror $base (older than 30 days)"
        rm -rf "$d"
      fi
      ;;
  esac
done

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
rm -rf .spm-packages/repositories/v[0-9]*.*
rm -rf .spm-packages/checkouts/vauchi-platform-swift
rm -rf .spm-packages/checkouts/v[0-9]*.*
rm -rf .spm-packages/manifests/vauchi-platform-swift-*
rm -rf .spm-packages/manifests/v[0-9]*.*
rm -rf .spm-packages/artifacts/vauchi-platform-swift
rm -rf .spm-packages/artifacts/v[0-9]*.*
rm -f  .spm-packages/workspace-state.json
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/vauchi-platform-swift-* 2>/dev/null || true
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/v[0-9]*.* 2>/dev/null || true
rm -rf ~/Library/org.swift.swiftpm/repositories/vauchi-platform-swift-* 2>/dev/null || true
rm -rf ~/Library/org.swift.swiftpm/repositories/v[0-9]*.* 2>/dev/null || true
rm -rf ~/.cache/org.swift.swiftpm/repositories/vauchi-platform-swift-* 2>/dev/null || true
rm -rf ~/.cache/org.swift.swiftpm/repositories/v[0-9]*.* 2>/dev/null || true
rm -rf ~/.swiftpm/repositories/vauchi-platform-swift-* 2>/dev/null || true
rm -rf ~/.swiftpm/repositories/v[0-9]*.* 2>/dev/null || true
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
# build:debug and build:release both use the shared CFGLOCK path below.
# SPM_ISOLATE_HOME was previously used to avoid a cross-pipeline mirror-config
# race, but xcodebuild on the nell runner resolves SPM using the real user
# HOME regardless of the env var, so an isolated config is ineffective.
# build:debug jobs are already serialized by the ios-spm-v5 resource_group,
# and the CFGLOCK below also serializes against macos bump pipelines.
if [ -n "${SPM_ISOLATE_HOME:-}" ]; then
  CFG_DIR="$SPM_ISOLATE_HOME/Library/org.swift.swiftpm/configuration"
  mkdir -p "$CFG_DIR"
  printf '%s' "$MIRROR_JSON" > "$CFG_DIR/mirrors.json"
  HOME="$SPM_ISOLATE_HOME" xcodebuild -project Vauchi.xcodeproj -scheme Vauchi \
    -clonedSourcePackagesDirPath .spm-packages \
    -derivedDataPath .derived-data \
    -resolvePackageDependencies
  echo "  SPM resolve OK (private config $CFG_DIR — no shared file, no CFGLOCK)"
  exit 0
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
