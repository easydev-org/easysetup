#!/bin/bash
# build-node.sh <version> <outdir> — pack a complete node tree into a tarball.
#
# The tarball's root is opt/setup/node/..., so the consumer can `tar -xJf ... -C /`
# without knowing anything about this repository's layout.
set -euo pipefail

VERSION="$1"
OUT="$2"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/node"
mkdir -p "$ROOT"

URL="https://nodejs.org/dist/v${VERSION}/node-v${VERSION}-linux-x64.tar.xz"
echo "node: ${VERSION} <- ${URL}"
curl -fsSL --retry 3 --retry-delay 2 -o /tmp/node.tar.xz "$URL"
tar -xJf /tmp/node.tar.xz -C "$ROOT" --strip-components=1
rm -f /tmp/node.tar.xz

"$ROOT/bin/node" --version

mkdir -p "$OUT"
ASSET="$OUT/node-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "node: wrote $ASSET"
