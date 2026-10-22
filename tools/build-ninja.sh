#!/bin/bash
# build-ninja.sh <dir> <version> <outdir>
# Ninja is one static binary in a zip. Nothing to configure.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://github.com/ninja-build/ninja/releases/download/v${VERSION}/ninja-linux.zip"
echo "ninja: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/ninja.zip
unzip -q -o /tmp/ninja.zip -d "$ROOT/bin"
rm -f /tmp/ninja.zip
chmod +x "$ROOT/bin/ninja"

"$ROOT/bin/ninja" --version

mkdir -p "$OUT"
ASSET="$OUT/ninja-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "ninja: wrote $ASSET"
