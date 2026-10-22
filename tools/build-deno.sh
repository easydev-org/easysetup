#!/bin/bash
# build-deno.sh <dir> <version> <outdir>
# Deno ships one static binary in a zip. Nothing to compile or configure.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://github.com/denoland/deno/releases/download/v${VERSION}/deno-x86_64-unknown-linux-gnu.zip"
echo "deno: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/deno.zip
unzip -q -o /tmp/deno.zip -d "$ROOT/bin"
rm -f /tmp/deno.zip
chmod +x "$ROOT/bin/deno"

"$ROOT/bin/deno" --version | head -1

mkdir -p "$OUT"
ASSET="$OUT/deno-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "deno: wrote $ASSET"
