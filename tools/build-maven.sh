#!/bin/bash
# build-maven.sh <dir> <version> <outdir>
#
# Apache Maven from the official -bin.tar.gz. A JRE is NOT bundled: maven is
# installed next to a java-* setup and finds it through JAVA_HOME, which
# /opt/setup/env.sh exports.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://repo1.maven.org/maven2/org/apache/maven/apache-maven/${VERSION}/apache-maven-${VERSION}-bin.tar.gz"
echo "maven: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/maven.tar.gz
# The archive's root is apache-maven-<version>/.
tar -xzf /tmp/maven.tar.gz -C "$ROOT" --strip-components=1
rm -f /tmp/maven.tar.gz

"$ROOT/bin/mvn" -version 2>&1 | head -2

mkdir -p "$OUT"
ASSET="$OUT/maven-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "maven: wrote $ASSET"
