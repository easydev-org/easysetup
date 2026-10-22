#!/bin/bash
# build-cabal.sh <dir> <version> <outdir>
# cabal-install publishes a static binary tarball; its root is a directory.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://downloads.haskell.org/~cabal/cabal-install-${VERSION}/cabal-install-${VERSION}-x86_64-linux-alpine3_12.tar.xz"
echo "cabal: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/cabal.tar.xz
tar -xJf /tmp/cabal.tar.xz -C "$ROOT/bin"
rm -f /tmp/cabal.tar.xz
chmod +x "$ROOT/bin/cabal"

"$ROOT/bin/cabal" --version | head -1

mkdir -p "$OUT"
ASSET="$OUT/cabal-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "cabal: wrote $ASSET"
