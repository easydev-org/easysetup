#!/bin/bash
# build-node.sh <id> <version> <outdir>
#
# Packs a complete node tree at opt/setup/<id>/..., where <id> is the matrix id
# (e.g. node-22). The versioned directory is what lets node-22 and node-24 live
# side by side.
set -euo pipefail

ID="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$ID"
mkdir -p "$ROOT"

URL="https://nodejs.org/dist/v${VERSION}/node-v${VERSION}-linux-x64.tar.xz"
echo "node: $ID $VERSION <- $URL"
curl -fsSL --retry 3 --retry-delay 2 -o /tmp/node.tar.xz "$URL"
tar -xJf /tmp/node.tar.xz -C "$ROOT" --strip-components=1
rm -f /tmp/node.tar.xz

"$ROOT/bin/node" --version

mkdir -p "$OUT"
ASSET="$OUT/node-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "node: wrote $ASSET"
