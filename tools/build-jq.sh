#!/bin/bash
# build-jq.sh <dir> <version> <outdir>
# jq publishes a bare binary, not an archive.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://github.com/jqlang/jq/releases/download/jq-${VERSION}/jq-linux-amd64"
echo "jq: $DIR $VERSION <- $URL"
fetch "$URL" "$ROOT/bin/jq"
chmod +x "$ROOT/bin/jq"

"$ROOT/bin/jq" --version

mkdir -p "$OUT"
ASSET="$OUT/jq-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "jq: wrote $ASSET"
