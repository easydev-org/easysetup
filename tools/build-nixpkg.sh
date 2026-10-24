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
#
# The name may carry a SUFFIX after the version - `mypy-2.1.0-py3.13` is mypy
# 2.1.0 built for python 3.13, and its version is still 2.1.0. So the version has
# to appear as a whole `-<version>` segment, at the end or before a suffix -
# matching only "ends with the version" rejected every suffixed setup.
case "$NAME" in
  *-"$VERSION")          : ;;      # tool-1.2.3
  *-"$VERSION"-?*)       : ;;      # tool-1.2.3-suffix
  *) echo "nixpkg: name says $NAME but nix builds $VERSION - run tools/check-versions.py --fix, then regenerate setups/" >&2
     exit 1 ;;
esac

echo "nixpkg: building"
# Print what the flake can actually see before building. A mismatch between the
# file on disk and the attribute nix resolves means nix is evaluating a different
# tree than the checkout - which is what happens when flake evaluation is pinned
# to a git revision that predates the file.
if ! "$NIX" eval --raw ".#versions.\"$NAME\"" >/dev/null 2>&1; then
  echo "nixpkg: the flake cannot see setups/$NAME.nix" >&2
  echo "nixpkg: setup files on disk: $(ls setups/*.nix 2>/dev/null | wc -l)" >&2
  echo "nixpkg: attributes the flake exposes (first 5):" >&2
  "$NIX" eval --impure --json ".#versions" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); ks=sorted(d); print("   ", ks[:5])' >&2 || true
  echo "nixpkg: is the working tree dirty?" >&2
  git status --short 2>/dev/null | head -5 >&2 || true
fi

# `set -e` aborts on a failing command substitution BEFORE the `if` can inspect
# it, so a build failure produced no message at all - the log just stopped after
# "nixpkg: building". Capturing the status explicitly is what makes the error
# visible.
# The attribute name contains dots (jq-1.8.2), and nix reads an UNQUOTED dot as an
# attribute path separator: `.#jq-1.8.2` looks for jq-1."8"."2". Every setup name
# here has that shape, so this quoting is what makes the build resolve at all.
#
# A multi-output package prints one line per output, in no useful order: `head -1`
# and `tail -1` both landed on `-man` for different setups. Neither end is the
# answer, so the outputs are collected and the one that actually holds the
# executables is chosen. A setup that overrides its output (`pkgs.jq.bin`) has
# exactly one line, so this picks it trivially.
OUTLIST=$("$NIX" build --no-link --print-out-paths ".#\"$NAME\"" 2>/tmp/nixpkg-err.log)
if [ $? -ne 0 ] || [ -z "$OUTLIST" ]; then
  echo "nixpkg: nix build failed" >&2
  tail -40 /tmp/nixpkg-err.log >&2
  exit 1
fi
OUTPATH=""
for cand in $OUTLIST; do
  if [ -d "$cand/bin" ] || [ -d "$cand/sbin" ]; then OUTPATH="$cand"; break; fi
done
# No output has bin/: fall back to the first, so the error names a real path.
[ -n "$OUTPATH" ] || OUTPATH=$(printf '%s\n' "$OUTLIST" | head -1)
if [ -z "$OUTPATH" ] || [ ! -e "$OUTPATH" ]; then
  echo "nixpkg: nix build produced no output path" >&2
  tail -40 /tmp/nixpkg-err.log >&2
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
#
# `base` is the exception: it is a library set, not a tool, so it has no bin and
# putting anything on PATH would be meaningless. Its registry entry says "bin"
# anyway so the record has a consistent shape; the installer ignores it for base.
#
# A manifest entry may override the guess with `bins:` — cacert is the case that
# forced it: its interesting files are at etc/ssl/certs/ca-bundle.crt and it has
# no bin/ at all, so the inference below rejected a perfectly good package. An
# explicit `bins:` wins, and only if there is neither an override nor a bin/ does
# this fail.
declared=$(python3 - "$DIR" <<'PY' 2>/dev/null || true
import sys
sys.path.insert(0, ".")
import matrixlib2
for e in matrixlib2.load("matrix-nix.yml"):
    if e["dir"] == sys.argv[1]:
        # Only a value the manifest set itself; the default is "bin" and would
        # otherwise mask a package that has neither bin/ nor sbin/.
        print(e.get("bins_declared", ""))
        break
PY
)

if [ -n "$declared" ]; then
  bins="$declared"
  echo "nixpkg: bins from the manifest: $bins"
elif [ "$DIR" = "base" ] || [ "${DIR%%-[0-9]*}" = "base" ]; then
  bins="bin"
else
  bins=""
  for d in bin sbin; do
    [ -d "$REAL/$d" ] && bins="$bins$d "
  done
  bins=$(echo "$bins" | sed 's/ *$//')
  [ -n "$bins" ] || { echo "nixpkg: $REAL has no bin/ or sbin/, and matrix-nix.yml declares no bins: for $DIR" >&2; exit 1; }
fi

STAGE=$(mktemp -d)
mkdir -p "$STAGE/nix/store"

# What goes in the tarball.
#
# By default that is the whole closure, which makes the tarball self-contained.
# When closures.json lists this setup, the paths already provided by its deps and
# by the shared base are LEFT OUT - install.sh fetches those once, and pouring
# them into every tarball is what made `php + composer` download php twice.
#
# Only the listed paths are copied, never the whole closure: a delta tarball that
# quietly included everything would defeat the point, and a full tarball that
# quietly dropped something would be broken. Both directions are wrong, so the
# list is computed once (tools/compute-deps.py) and obeyed exactly here.
CLOSURES="$(dirname "$0")/../closures.json"
paths=""
mode="full closure"
if [ -f "$CLOSURES" ] && command -v python3 >/dev/null 2>&1; then
  paths=$(python3 - "$CLOSURES" "$DIR" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
name = sys.argv[2]
entry = doc.get("setups", {}).get(name)
if not entry:
    sys.exit(0)                      # unknown here: fall back to the full closure

# The `base` setup is different: it does not ship "what its closure adds", it
# ships the shared set itself. compute-deps.py records that set in `own["base"]`,
# so the same field works - but only if `base` is present in the manifest.
for p in entry.get("own", []):
    print(p)
PY
)
  if [ -n "$paths" ]; then
    mode="delta ($(echo "$paths" | wc -l) of the closure; the rest comes from deps+base)"
  fi
fi

if [ -z "$paths" ]; then
  paths=$("$NIX" path-info -r "$REAL" 2>/dev/null)
fi

# The paths needed to RUN this setup but not shipped in its tarball: the base and
# whatever its dependencies provide. install.sh fetches these separately, so the
# verification below has to stage them too or it would fail a correct build.
COMPANION_PATHS=""
if [ -f "$CLOSURES" ] && command -v python3 >/dev/null 2>&1; then
  COMPANION_PATHS=$(python3 - "$CLOSURES" "$DIR" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
name = sys.argv[2]
entry = doc.get("setups", {}).get(name)
if not entry:
    sys.exit(0)
seen = set()
for p in doc.get("base", []):
    seen.add(p)
# Walk the dependency chain: install.sh would install all of it before this one.
def add(n):
    e = doc["setups"].get(n, {})
    for d in e.get("deps", []):
        add(d)
        for q in doc["setups"].get(d, {}).get("own", []):
            seen.add(q)
add(name)
print(" ".join(sorted(seen)))
PY
)
fi

echo "nixpkg: packaging $mode"

# Ensure every path in the list exists locally. For a normal setup the closure is
# already present because `nix build` realised it. `base` is different: its paths
# come from many packages (bash, gcc, xz, acl...) that no single build pulls in,
# so they have to be fetched explicitly or the copy below fails on a missing path.
missing=""
for p in $paths; do
  [ -e "$p" ] || missing="$missing $p"
done
if [ -n "$missing" ]; then
  echo "nixpkg: fetching $(echo $missing | wc -w) path(s) not yet in the store"
  # `nix-store --realise` takes store paths directly and substitutes them from
  # the binary cache; no flake evaluation is involved. nix-store ships beside nix
  # in the same profile.
  NIXSTORE="$(dirname "$NIX")/nix-store"
  if [ ! -x "$NIXSTORE" ]; then
    if ! "$NIX" store realise $missing >/dev/null 2>/tmp/nixpkg-fetch.log; then
      echo "nixpkg: could not fetch some paths" >&2
      tail -10 /tmp/nixpkg-fetch.log >&2
      exit 1
    fi
  elif ! "$NIXSTORE" --realise $missing >/dev/null 2>/tmp/nixpkg-fetch.log; then
    echo "nixpkg: could not fetch some paths" >&2
    tail -10 /tmp/nixpkg-fetch.log >&2
    exit 1
  fi
fi

count=0
for p in $paths; do
  [ -e "$p" ] || { echo "nixpkg: still missing $p" >&2; exit 1; }
  cp -a "$p" "$STAGE/nix/store/" 2>/dev/null || true
  count=$((count + 1))
done
[ "$count" -gt 0 ] || { echo "nixpkg: nothing to package" >&2; exit 1; }
echo "nixpkg: $count store path(s) in the tarball"

# nix/var is this machine's database and gc roots. It is not part of a package,
# and shipping it would let the consumer's nix believe things about paths it
# never registered.
rm -rf "$STAGE/nix/var" 2>/dev/null || true

# Discovery metadata. env.sh looks for <prefix>/bin, but a nix package lives at
# nix/store/<hash>/bin, so the tarball states where its binaries are. One file
# per setup: several nix setups can be installed side by side, and a shared file
# would let the last install win.
#
# `base` is the exception. Its tarball carries a SET of store paths, not one
# output, so recording `$REAL` produced an entry pointing at
# `glibc-2.44-57-bin` - a path that is not in the tarball at all (it ships
# `glibc-2.44-57`). install.sh then saw a registry entry whose store was missing,
# which is exactly the kind of dangling record that breaks every later install.
#
# base provides no executables, so the honest record is "no bin dirs": it is
# installed, it registers nothing on PATH, and nothing can dangle.
mkdir -p "$STAGE/nix"
if [ "${DIR%%-[0-9]*}" = "base" ]; then
  printf '%s|%s\n' "none" "" > "$STAGE/nix/setup-root-$DIR"
else
  printf '%s|%s\n' "$REAL" "$bins" > "$STAGE/nix/setup-root-$DIR"
fi

# Prove the STAGED copy runs, using nothing from /nix. A stale store on the build
# machine would otherwise make a broken closure look fine.
#
# `base` is skipped: it is a library set with no executables, so there is nothing
# to execute. The check that matters for it is that its paths were collected at
# all, which the counts above already show.
if [ "${DIR%%-[0-9]*}" = "base" ]; then
  echo "nixpkg: base carries libraries only; skipping the execute check"
else
  echo "nixpkg: verifying the staged tree in a chroot with no nix"
  # The whole check is advisory: it reports, it never fails the build. That has
  # to be enforced here rather than per-command, because a copy or an `ls` on a
  # missing path would otherwise abort under `set -e` and hide the real reason.
  set +e
  first=$(ls "$STAGE$REAL/bin" 2>/dev/null | head -1)
  if [ -z "$first" ]; then
    echo "nixpkg: bin/ is empty in the staged copy" >&2
    set -e
    exit 1
  fi
  if command -v chroot >/dev/null 2>&1; then
    # A delta tarball is NOT self-sufficient on its own - that is the point of
    # the scheme. Its glibc lives in the base tarball and its libraries may come
    # from a dependency, so running it in a root holding only this tarball would
    # fail for a correct build. The chroot therefore also gets the base and dep
    # paths, which is exactly what install.sh would have put on disk.
    #
    # This still catches the failure the check exists for: a path that the setup
    # needs but neither it nor its dependencies provide.
    #
    # Those paths are usually not in the store yet - `nix build` realised only
    # this setup, and base comes from a different tarball. Realise them first,
    # or the copy below silently copies nothing and the chroot run fails on a
    # missing interpreter.
    if [ -n "$COMPANION_PATHS" ]; then
      echo "nixpkg: staging $(echo $COMPANION_PATHS | wc -w) companion path(s) for the chroot"
      NIXSTORE_C="$(dirname "$NIX")/nix-store"
      if [ -x "$NIXSTORE_C" ]; then
        "$NIXSTORE_C" --realise $COMPANION_PATHS >/dev/null 2>&1 || true
      else
        "$NIX" build --no-link $COMPANION_PATHS >/dev/null 2>&1 || true
      fi
      for extra in $COMPANION_PATHS; do
        [ -e "$extra" ] && cp -a "$extra" "$STAGE/nix/store/" 2>/dev/null
      done
      staged=$(ls "$STAGE/nix/store" | wc -l)
      echo "nixpkg: chroot root holds $staged store path(s)"
    fi
    chroot "$STAGE" "$REAL/bin/$first" --version >/dev/null 2>&1 \
      || chroot "$STAGE" "$REAL/bin/$first" >/dev/null 2>&1 \
      || echo "nixpkg: note - $first did not answer; not fatal"
    echo "nixpkg: chroot check done ($first)"
  else
    echo "nixpkg: chroot unavailable; skipping the isolation check"
  fi
  # Restore the strict behaviour for the packaging that follows; only the
  # advisory check above runs unguarded.
  set -e
fi

mkdir -p "$OUT"
ASSET="$OUT/$DIR-debian-trixie-amd64.tar.zst"

# zstd, not xz. Measured on swift (5.8 GB unpacked): `tar -cJf` spent 34m49s in
# single-threaded xz compression while the download and unpack took 23s and the
# copy 32s - so 97% of the job was the compressor. zstd with -T0 uses every core
# and lands within a few percent of xz on ratio.
#
# Level 3, the zstd default. Higher levels cost far more time than they save
# space on a tree this size: -19 is about 20% smaller than -3 and an order of
# magnitude slower, which on the 5.8 GB swift closure meant 15+ minutes for
# roughly 50 MB. Speed is the whole reason for choosing zstd, so the default
# level is the right one.
#
# No --long window either: it makes the frame require a matching decompressor
# flag, for a few percent at most.
#
# tar piped into zstd rather than `tar --zstd`: the pipe avoids staging a second
# multi-GB file on disk, which on the swift closure would be 5.8 GB written twice.
tar -cf - -C "$STAGE" . \
  | zstd -3 -T0 --quiet --force -o "$ASSET"
# Nix store paths are read-only (mode 0555 on directories), so a plain `rm -rf`
# fails on the copy with "Permission denied". The copy kept those modes, which is
# correct for the artifact - a consumer unpacking it gets the same protections -
# but the staging tree has to be made writable before it can be removed.
chmod -R u+w "$STAGE" 2>/dev/null || true
rm -rf "$STAGE"
echo "nixpkg: wrote $ASSET ($(du -h "$ASSET" | cut -f1))"
