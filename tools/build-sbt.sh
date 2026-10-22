#!/bin/bash
# build-sbt.sh <dir> <version> <outdir>
# sbt ships a launcher + libs in a tgz. It needs a JRE, supplied by a java-*
# setup, so it is not run here.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://github.com/sbt/sbt/releases/download/v${VERSION}/sbt-${VERSION}.tgz"
echo "sbt: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/sbt.tgz
tar -xzf /tmp/sbt.tgz -C "$ROOT" --strip-components=1
rm -f /tmp/sbt.tgz

test -x "$ROOT/bin/sbt" || { echo "sbt: bin/sbt missing" >&2; exit 1; }
ls "$ROOT"/bin/sbt-launch.jar >/dev/null 2>&1 || \
  ls "$ROOT"/bin/*.jar >/dev/null 2>&1 || {
    echo "sbt: launcher jar missing" >&2; exit 1; }
echo "sbt: bin/sbt + launcher jar present (JRE comes from a java-* setup)"

mkdir -p "$OUT"
ASSET="$OUT/sbt-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "sbt: wrote $ASSET"
