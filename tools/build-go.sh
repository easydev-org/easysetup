#!/bin/bash
# build-go.sh <version> <outdir>
set -euo pipefail

VERSION="$1"
OUT="$2"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/go"
mkdir -p "$ROOT"

URL="https://go.dev/dl/go${VERSION}.linux-amd64.tar.gz"
echo "go: ${VERSION} <- ${URL}"
curl -fsSL --retry 3 --retry-delay 2 -o /tmp/go.tar.gz "$URL"
tar -xzf /tmp/go.tar.gz -C "$ROOT" --strip-components=1
rm -f /tmp/go.tar.gz

"$ROOT/bin/go" version

mkdir -p "$OUT"
ASSET="$OUT/go-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "go: wrote $ASSET"
