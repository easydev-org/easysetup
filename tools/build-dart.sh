#!/bin/bash
# build-dart.sh <dir> <version> <outdir>
# The SDK zip's root is dart-sdk/, so strip one component.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://storage.googleapis.com/dart-archive/channels/stable/release/${VERSION}/sdk/dartsdk-linux-x64-release.zip"
echo "dart: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/dart.zip
unzip -q -o /tmp/dart.zip -d /tmp/dart-x
cp -a /tmp/dart-x/dart-sdk/. "$ROOT"/
rm -rf /tmp/dart.zip /tmp/dart-x

"$ROOT/bin/dart" --version 2>&1 | head -1

mkdir -p "$OUT"
ASSET="$OUT/dart-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "dart: wrote $ASSET"
