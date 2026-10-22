#!/bin/bash
# build-buf.sh <dir> <version> <outdir>
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT/bin"

URL="https://github.com/bufbuild/buf/releases/download/v${VERSION}/buf-Linux-x86_64"
echo "buf: $DIR $VERSION <- $URL"
fetch "$URL" "$ROOT/bin/buf"
chmod +x "$ROOT/bin/buf"

"$ROOT/bin/buf" --version

mkdir -p "$OUT"
ASSET="$OUT/buf-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "buf: wrote $ASSET"
