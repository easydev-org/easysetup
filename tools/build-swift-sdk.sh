#!/bin/bash
# build-swift-sdk.sh <dir> <version> <outdir>
#
# One script for the three Swift SDKs, told apart by the setup's tool name:
#
#   swift-sdk-static-linux   -> static-sdk
#   swift-sdk-wasm           -> wasm-sdk
#   swift-sdk-android        -> android-sdk
#
# An SDK is bytecode + headers that a Swift compiler drives; it has no
# executable of its own, so it `requires` the swift toolchain (declared in
# matrix.yml). Installing an SDK therefore installs Swift first.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

TOOL="${DIR%-$VERSION}"
case "$TOOL" in
  swift-sdk-static-linux) CHANNEL="static-sdk";  STEM="static-linux-0.1.0" ;;
  swift-sdk-wasm)         CHANNEL="wasm-sdk";    STEM="wasm" ;;
  swift-sdk-android)      CHANNEL="android-sdk"; STEM="android" ;;
  *) echo "swift-sdk: unexpected setup name '$DIR'" >&2; exit 1 ;;
esac

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://download.swift.org/swift-${VERSION}-release/${CHANNEL}/swift-${VERSION}-RELEASE/swift-${VERSION}-RELEASE_${STEM}.artifactbundle.tar.gz"
echo "swift-sdk: $DIR ($CHANNEL) <- $URL"
fetch "$URL" /tmp/sdk.tar.gz

rm -rf /tmp/sdk-x && mkdir -p /tmp/sdk-x
tar -xzf /tmp/sdk.tar.gz -C /tmp/sdk-x
rm -f /tmp/sdk.tar.gz

# The tarball's single top entry is the .artifactbundle directory; keep it as a
# unit, because that is what `swift build --swift-sdk` expects to find.
BUNDLE=$(find /tmp/sdk-x -maxdepth 1 -mindepth 1 -name '*.artifactbundle' | head -1)
[ -n "$BUNDLE" ] || { echo "swift-sdk: no .artifactbundle in the tarball" >&2; ls /tmp/sdk-x >&2; exit 1; }
cp -a "$BUNDLE" "$ROOT"/
rm -rf /tmp/sdk-x

# Prove the bundle is intact the way swift checks it: a manifest plus payload.
BDIR=$(find "$ROOT" -maxdepth 1 -mindepth 1 -name '*.artifactbundle' | head -1)
test -f "$BDIR/info.json" || { echo "swift-sdk: info.json missing" >&2; exit 1; }
test -d "$BDIR/$STEM" || {
  echo "swift-sdk: payload directory '$STEM' missing" >&2
  ls "$BDIR" >&2; exit 1; }
echo "swift-sdk: $(basename "$BDIR") present with info.json"

mkdir -p "$OUT"
ASSET="$OUT/${TOOL}-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "swift-sdk: wrote $ASSET"
