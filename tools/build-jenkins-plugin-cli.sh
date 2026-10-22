#!/bin/bash
# build-jenkins-plugin-cli.sh <dir> <version> <outdir>
#
# jenkins-plugin-cli is the plugin-installation-manager-tool: a single jar that
# resolves and downloads Jenkins plugins. It is pure Java, so like conan it
# depends on a runtime rather than bundling one - `requires: [java@>=17 <22]`
# puts a JRE on PATH first.
#
# The jar is invoked as `java -jar`; the shipped launcher wraps that so a
# consumer can call `jenkins-plugin-cli` directly.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT/lib" "$ROOT/bin"

URL="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${VERSION}/jenkins-plugin-manager-${VERSION}.jar"
echo "jenkins-plugin-cli: $DIR $VERSION <- $URL"
fetch "$URL" "$ROOT/lib/jenkins-plugin-manager.jar"

# A jar is a zip - check it really is one rather than trusting the download.
head -c 2 "$ROOT/lib/jenkins-plugin-manager.jar" | grep -q 'PK' || {
  echo "jenkins-plugin-cli: downloaded file is not a jar" >&2; exit 1; }

cat > "$ROOT/bin/jenkins-plugin-cli" <<'LAUNCHER'
#!/bin/sh
# jenkins-plugin-cli launcher: a jar plus whatever java the consumer installed.
self=$(dirname "$(readlink -f "$0")")
root=$(cd "$self/.." && pwd)
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA="$JAVA_HOME/bin/java"
else
  JAVA=java
fi
exec "$JAVA" -jar "$root/lib/jenkins-plugin-manager.jar" "$@"
LAUNCHER
chmod +x "$ROOT/bin/jenkins-plugin-cli"
echo "jenkins-plugin-cli: jar is $(du -h "$ROOT/lib/jenkins-plugin-manager.jar" | cut -f1)"

mkdir -p "$OUT"
ASSET="$OUT/jenkins-plugin-cli-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "jenkins-plugin-cli: wrote $ASSET"
