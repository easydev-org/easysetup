#!/bin/bash
# build-crystal.sh <dir> <version> <outdir>
#
# crystal publishes two flavours; the -bundled one carries the LLVM and libs it
# needs, so it is the one that works on a distro whose LLVM differs. Its root is
# crystal-<ver>-1/.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-relocate.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://github.com/crystal-lang/crystal/releases/download/${VERSION}/crystal-${VERSION}-1-linux-x86_64-bundled.tar.gz"
echo "crystal: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/crystal.tar.gz
rm -rf /tmp/crystal-x && mkdir -p /tmp/crystal-x
tar -xzf /tmp/crystal.tar.gz -C /tmp/crystal-x
rm -f /tmp/crystal.tar.gz
SRC=$(find /tmp/crystal-x -maxdepth 1 -mindepth 1 -type d | head -1)
[ -n "$SRC" ] || { echo "crystal: unexpected tarball layout" >&2; ls /tmp/crystal-x >&2; exit 1; }
cp -a "$SRC"/. "$ROOT"/
rm -rf /tmp/crystal-x

# CRYSTAL_PATH is compiled in; the wrapper scripts record the build prefix.
n=$(relocate_scripts "$ROOT" "/opt/setup/$DIR")
echo "crystal: rewrote the prefix in $n script(s)"

CRYSTAL_PATH="$ROOT/lib/crystal" "$ROOT/bin/crystal" --version | head -2

mkdir -p "$OUT"
ASSET="$OUT/crystal-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "crystal: wrote $ASSET"
