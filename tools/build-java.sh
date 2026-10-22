#!/bin/bash
# build-java.sh <version> <outdir>
#
# Adoptium Temurin JDK. The API resolves the exact build for a version string.
set -euo pipefail

VERSION="$1"
OUT="$2"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/java"
mkdir -p "$ROOT"

FEATURE="${VERSION%%.*}"
URL="https://api.adoptium.net/v3/binary/version/jdk-${VERSION}/linux/x64/jdk/hotspot/normal/eclipse"
echo "java: ${VERSION} <- Adoptium"

if ! curl -fsSL --retry 3 --retry-delay 2 -o /tmp/jdk.tar.gz "$URL"; then
  echo "java: exact ${VERSION} unavailable; using latest ${FEATURE} GA" >&2
  URL="https://api.adoptium.net/v3/binary/latest/${FEATURE}/ga/linux/x64/jdk/hotspot/normal/eclipse"
  curl -fsSL --retry 3 --retry-delay 2 -o /tmp/jdk.tar.gz "$URL"
fi
tar -xzf /tmp/jdk.tar.gz -C "$ROOT" --strip-components=1
rm -f /tmp/jdk.tar.gz

"$ROOT/bin/java" -version

mkdir -p "$OUT"
# "+" is not safe in an asset name, so it becomes "-".
SAFE=$(echo "$VERSION" | tr '+' '-')
ASSET="$OUT/java-${SAFE}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "java: wrote $ASSET"
