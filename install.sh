#!/bin/bash
# install.sh — install easysetup toolchains from prebuilt nix closures.
#
#   ./install.sh node python swift
#   ./install.sh --list
#
# WHAT THIS SCRIPT DOES, in full:
#   1. resolve the requested names against the manifest,
#   2. download each setup's tarball,
#   3. verify its sha256,
#   4. unpack it at /.
#
# That is the entire install. There is no apt step, no dependency resolution and
# no per-tool special case, because a setup is a nix closure: its libraries, its
# loader and its data files are already inside the tarball, and its paths are
# absolute /nix/store paths that cannot collide (the hash is the isolation).
#
# Two consequences worth stating, since both were different before:
#
#   * every setup lands at /nix/store/<hash>-<name>/, NOT under /opt/setup. That
#     path is baked into every binary as the ELF interpreter and rpath; moving it
#     breaks the tree, so the layout is kept exactly as nix produced it.
#   * each tarball writes /nix/setup-root-<dir>, which is how gen-env.sh finds
#     the binaries. One file per setup, so several setups can coexist.
#
# The bootstrap packages (curl, zstd, python3, ca-certificates) are the caller's
# job: this script cannot download anything without curl, and cannot unpack a
# .tar.zst without zstd. The provided action installs them first.
set -euo pipefail

REPO="${EASYSETUP_REPO:-easydev-org/easysetup}"
RAW="https://raw.githubusercontent.com/${REPO}/main"
BASE="https://github.com/${REPO}/releases/download"

command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "install.sh: python3 is required" >&2; exit 1; }
command -v zstd >/dev/null || { echo "install.sh: zstd is required to unpack .tar.zst" >&2; exit 1; }

# The manifest and its parser are fetched together and used by the SAME code the
# release pipeline uses. An awk re-implementation here is what let the two drift
# apart before, so there is deliberately only one parser.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 3 -o "$WORK/matrix-nix.yml" "$RAW/matrix-nix.yml" || {
  echo "install.sh: cannot read the manifest" >&2; exit 1; }
curl -fsSL --retry 3 -o "$WORK/matrixlib2.py" "$RAW/matrixlib2.py" || {
  echo "install.sh: cannot read matrixlib2.py" >&2; exit 1; }

mlib() { ( cd "$WORK" && python3 matrixlib2.py "$@" ); }

if [ "$#" -eq 0 ]; then
  echo "install.sh: name at least one setup; 'install.sh --list' shows them" >&2
  exit 2
fi

if [ "$1" = "--list" ]; then
  mlib list
  exit 0
fi

installed=""

for name in "$@"; do
  id=$(mlib resolve "$name") || {
    echo "install.sh: cannot resolve '$name'" >&2
    echo "            available: $(mlib list | tr '\n' ' ')" >&2
    exit 2
  }
  artifact=$(mlib get "$id" artifact)
  tool=$(mlib get "$id" tool)
  version=$(mlib get "$id" version)

  echo "==> $id ($tool $version)"

  # Idempotence. install.sh runs once per `uses:` step and the same setup is
  # legitimately requested twice; re-downloading hundreds of MB to unpack over
  # itself is pointless. The registry file doubles as the "already installed"
  # marker because it is written last, by the tarball itself.
  if [ -f "/nix/setup-root-$id" ]; then
    echo "    already unpacked (/nix/setup-root-$id exists), skipping"
    installed="$installed $id"
    continue
  fi

  url="$BASE/$id/$artifact"
  echo "    fetch: $url"
  curl -fsSL --http1.1 --retry 3 --retry-delay 2 -o "$WORK/asset" "$url" || {
    echo "install.sh: download failed for $artifact" >&2; exit 1; }

  # The pin lives beside the release, not in the manifest: CI computes it from
  # the tarball it just produced, so it cannot describe a file that was never
  # uploaded.
  curl -fsSL --retry 3 -o "$WORK/sha" "$BASE/$id/$artifact.sha256" || {
    echo "install.sh: no sha256 published for $id; refusing to unpack" >&2
    exit 1; }
  expected=$(cut -d' ' -f1 "$WORK/sha")
  echo "$expected  $WORK/asset" | sha256sum -c - >/dev/null || {
    echo "install.sh: sha256 mismatch for $artifact" >&2; exit 1; }

  # Unpack at /. The archive carries nix/store/... and nix/setup-root-<dir>;
  # both must land at the root exactly as recorded.
  # Plain zstd: the tarballs are compressed at the default window, so any zstd
  # can read them. Piping zstd into tar extracts while decompressing instead of
  # buffering a multi-GB tree first.
  zstd -d --quiet -c "$WORK/asset" | tar -xf - -C /
  rm -f "$WORK/asset" "$WORK/sha"

  [ -f "/nix/setup-root-$id" ] || {
    echo "install.sh: $artifact did not produce /nix/setup-root-$id" >&2
    exit 1; }
  echo "    unpacked $(cut -d'|' -f1 "/nix/setup-root-$id")"
  installed="$installed $id"
done

# Regenerate env.sh from EVERYTHING present, not just this run: install.sh is
# invoked once per `uses:` step, so generating from "$installed" would make the
# last call erase what earlier ones installed.
curl -fsSL --retry 3 -o "$WORK/gen-env.sh" "$RAW/tools/gen-env.sh" || {
  echo "install.sh: cannot fetch gen-env.sh" >&2; exit 1; }
bash "$WORK/gen-env.sh" /opt/setup/env.sh

echo "==> installed:$installed"
echo "    now run:  . /opt/setup/env.sh"
