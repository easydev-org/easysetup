#!/bin/bash
# build-gradle.sh <dir> <version> <outdir>
#
# Gradle from its -bin.zip. Gradle carries its own launcher and downloads a
# JDK only if it cannot find one, so a java-* setup next to it is the intended
# arrangement.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://services.gradle.org/distributions/gradle-${VERSION}-bin.zip"
echo "gradle: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/gradle.zip
unzip -q /tmp/gradle.zip -d /tmp/gradle-x
# The zip's root is gradle-<version>/.
cp -a /tmp/gradle-x/gradle-"${VERSION}"/. "$ROOT"/
rm -rf /tmp/gradle.zip /tmp/gradle-x

"$ROOT/bin/gradle" --version 2>&1 | grep -E '^Gradle' | head -1

mkdir -p "$OUT"
ASSET="$OUT/gradle-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "gradle: wrote $ASSET"
