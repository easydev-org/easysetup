#!/bin/bash
# build-go.sh <id> <version> <outdir>
set -euo pipefail

ID="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$ID"
mkdir -p "$ROOT"

URL="https://go.dev/dl/go${VERSION}.linux-amd64.tar.gz"
echo "go: $ID $VERSION <- $URL"
curl -fsSL --retry 3 --retry-delay 2 -o /tmp/go.tar.gz "$URL"
tar -xzf /tmp/go.tar.gz -C "$ROOT" --strip-components=1
rm -f /tmp/go.tar.gz

"$ROOT/bin/go" version

mkdir -p "$OUT"
ASSET="$OUT/go-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "go: wrote $ASSET"
