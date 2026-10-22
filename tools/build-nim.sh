#!/bin/bash
# build-nim.sh <dir> <version> <outdir>
#
# Nim's linux_x64 tarball is a complete prebuilt tree (bin/, lib/, nim.cfg in
# bin/). Its root is nim-<version>/, so strip one component.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://nim-lang.org/download/nim-${VERSION}-linux_x64.tar.xz"
echo "nim: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/nim.tar.xz
tar -xJf /tmp/nim.tar.xz -C "$ROOT" --strip-components=1
rm -f /tmp/nim.tar.xz

# nim finds lib/ relative to bin/nim via bin/nim.cfg, which holds a RELATIVE
# path in the official tarball - so a move is safe. Assert the pieces exist.
test -x "$ROOT/bin/nim" || { echo "nim: bin/nim missing" >&2; exit 1; }
test -d "$ROOT/lib" || { echo "nim: lib/ missing" >&2; exit 1; }
"$ROOT/bin/nim" --version | head -1

mkdir -p "$OUT"
ASSET="$OUT/nim-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "nim: wrote $ASSET"
