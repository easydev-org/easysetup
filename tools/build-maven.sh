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

# Do NOT run `mvn -version` here. Maven refuses to start without a JAVA_HOME,
# and this tarball deliberately does not bundle a JRE - the consumer pairs it
# with a java-* setup and env.sh exports JAVA_HOME. Running it during the build
# would only test that no JRE is installed, which is the point. Verify the
# distribution's STRUCTURE instead.
test -x "$ROOT/bin/mvn" || { echo "maven: bin/mvn missing" >&2; exit 1; }
ls "$ROOT"/lib/maven-core-*.jar >/dev/null 2>&1 || {
  echo "maven: maven-core jar missing" >&2; exit 1; }
test -f "$ROOT/conf/settings.xml" || {
  echo "maven: conf/settings.xml missing" >&2; exit 1; }
echo "maven: bin/mvn + core jar + conf present (JRE comes from a java-* setup)"

mkdir -p "$OUT"
ASSET="$OUT/maven-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "maven: wrote $ASSET"
