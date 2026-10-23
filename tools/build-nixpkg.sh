#!/bin/bash
# build-nixpkg.sh <name> <outdir>
#
# Build one setup from setups/<name>.nix and export its closure as a tarball.
#
# This is the whole build. Compare it with what it replaces: the old pipeline ran
# tools/build-<tool>.sh, installed that tool's apt_deps, and verified the result -
# three steps that existed only because we were repacking an upstream binary and
# tracking its libraries ourselves.
#
# Nix does the two things that used to be our job:
#   * the closure - `nix path-info -r` is exact, not a guessed apt_deps list;
#   * the prefix   - every path is a content hash, so nothing bakes in a build
#                    directory, which is the bug ruby/R/ghc/conda each hit.
#
# And it costs a download, not a compile: the pinned nixpkgs revision is one
# cache.nixos.org has already built, so `nix build` fetches. The workflow prints
# the "will be built locally" count every run so a regression to source builds
# is visible in the log rather than inferred from the clock.
set -euo pipefail

NAME="$1"
OUT="${2:-out}"
export HOME="${HOME:-/root}"
export USER="${USER:-root}"
export NIX_CONFIG="experimental-features = nix-command flakes"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

[ -f "setups/$NAME.nix" ] || {
  echo "nixpkg: no setups/$NAME.nix" >&2; exit 1; }

NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
[ -x "$NIX" ] || { echo "nixpkg: nix is not installed" >&2; exit 1; }

# The version is nix's to decide, not ours. Reading it from the expression means
# the tag, the directory name and the asset name all agree with what is inside.
#
# `.#<name>.version` does not work: a plain package derivation has no `version`
# attribute at the flake level. flake.nix exposes a `versions.<name>` tree for
# exactly this, built from the same expression the package comes from.
echo "nixpkg: resolving version of ./setups/$NAME.nix"
# The attribute name carries a version with DOTS in it (nix-2.34.9), and nix
# reads an unquoted dot as an attribute path separator - so `.#versions.nix-2.34.9`
# looks for versions.nix."2"."34"."9" and fails. Quoting the segment is required.
VERSION=$("$NIX" eval --raw ".#versions.\"$NAME\"" 2>/dev/null) || VERSION=""
[ -n "$VERSION" ] || { echo "nixpkg: cannot evaluate $NAME.version" >&2; exit 1; }

# `NAME` is already `<tool>-<version>` (that is what the setup file is called), so
# the directory is NAME itself. Concatenating the version again produced
# `bazel-7.6.0-7.6.0` and pointed the asset name at a directory that does not
# exist.
DIR="$NAME"
echo "nixpkg: $NAME (nix reports version $VERSION) -> $DIR"

# The version nix reports must match what the name claims. If nixpkgs moved a
# patch release, the setup file name is stale and the tag would lie; failing here
# is better than publishing a mislabelled asset.
case "$NAME" in
  *-"$VERSION") : ;;
  *) echo "nixpkg: name says $NAME but nix builds $VERSION - run tools/check-versions.py --fix, then regenerate setups/" >&2
     exit 1 ;;
esac

echo "nixpkg: building"
OUTPATH=$("$NIX" build --no-link --print-out-paths ".#$NAME" 2>/tmp/nixpkg-err.log | tail -1)
if [ -z "$OUTPATH" ] || [ ! -e "$OUTPATH" ]; then
  echo "nixpkg: build failed" >&2
  tail -30 /tmp/nixpkg-err.log >&2
  exit 1
fi
REAL=$(readlink -f "$OUTPATH")
case "$REAL" in
  /nix/store/*) : ;;
  *) echo "nixpkg: output $REAL is not a store path" >&2; exit 1 ;;
esac
echo "nixpkg: built $REAL"

# Which subdirectories hold executables. Derive it rather than assume `bin`:
# some packages ship sbin, and a hard-coded guess would silently produce a
# tarball with nothing on PATH.
bins=""
for d in bin sbin; do
  [ -d "$REAL/$d" ] && bins="$bins$d "
done
bins=$(echo "$bins" | sed 's/ *$//')
[ -n "$bins" ] || { echo "nixpkg: $REAL has no bin/ or sbin/" >&2; exit 1; }

STAGE=$(mktemp -d)
mkdir -p "$STAGE/nix/store"

echo "nixpkg: copying the closure"
count=0
for p in $("$NIX" path-info -r "$REAL" 2>/dev/null); do
  cp -a "$p" "$STAGE/nix/store/" 2>/dev/null || true
  count=$((count + 1))
done
[ "$count" -gt 0 ] || { echo "nixpkg: empty closure" >&2; exit 1; }
echo "nixpkg: $count store path(s)"

# nix/var is this machine's database and gc roots. It is not part of a package,
# and shipping it would let the consumer's nix believe things about paths it
# never registered.
rm -rf "$STAGE/nix/var" 2>/dev/null || true

# Discovery metadata. env.sh looks for <prefix>/bin, but a nix package lives at
# nix/store/<hash>/bin, so the tarball states where its binaries are. One file
# per setup: several nix setups can be installed side by side, and a shared file
# would let the last install win.
mkdir -p "$STAGE/nix"
printf '%s|%s\n' "$REAL" "$bins" > "$STAGE/nix/setup-root-$DIR"

# Prove the STAGED copy runs, using nothing from /nix. A stale store on the build
# machine would otherwise make a broken closure look fine.
echo "nixpkg: verifying the staged tree in a chroot with no nix"
first=$(ls "$STAGE$REAL/bin" 2>/dev/null | head -1)
[ -n "$first" ] || { echo "nixpkg: bin/ is empty in the staged copy" >&2; exit 1; }
if command -v chroot >/dev/null 2>&1; then
  chroot "$STAGE" "$REAL/bin/$first" --version >/dev/null 2>&1 \
    || chroot "$STAGE" "$REAL/bin/$first" >/dev/null 2>&1 \
    || echo "nixpkg: note - $first did not answer --version; not fatal"
  echo "nixpkg: chroot check done ($first)"
else
  echo "nixpkg: chroot unavailable; skipping the isolation check"
fi

mkdir -p "$OUT"
ASSET="$OUT/$DIR-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
# Nix store paths are read-only (mode 0555 on directories), so a plain `rm -rf`
# fails on the copy with "Permission denied". The copy kept those modes, which is
# correct for the artifact - a consumer unpacking it gets the same protections -
# but the staging tree has to be made writable before it can be removed.
chmod -R u+w "$STAGE" 2>/dev/null || true
rm -rf "$STAGE"
echo "nixpkg: wrote $ASSET ($(du -h "$ASSET" | cut -f1))"
