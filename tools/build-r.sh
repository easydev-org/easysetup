#!/bin/bash
# build-r.sh <dir> <version> <outdir>
#
# Posit publishes prebuilt R as a .deb per ubuntu release. A .deb is an ar
# archive containing a data tarball, so the build EXTRACTS it with
# `dpkg-deb -x` rather than installing it onto the build host.
#
# The payload is rooted at ./opt/R/<version>/ (NOT /usr - posit installs R into
# /opt). That directory is what becomes /opt/setup/r-<version>, so R's own
# internal relative paths keep working.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://cdn.posit.co/r/ubuntu-2404/pkgs/r-${VERSION}_1_amd64.deb"
echo "r: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/r.deb

# dpkg-deb -x extracts without registering the package on this machine.
dpkg-deb -x /tmp/r.deb /tmp/r-x
rm -f /tmp/r.deb

# The deb extracts to <tmp>/opt/R/<version>/.
SRC=$(find /tmp/r-x -maxdepth 4 -type d -name "$VERSION" -path "*/opt/R/*" | head -1)
if [ -z "$SRC" ]; then
  echo "r: no opt/R/<version> directory in the .deb" >&2
  find /tmp/r-x -maxdepth 3 -type d | head -10 >&2
  exit 1
fi
cp -a "$SRC"/. "$ROOT"/
rm -rf /tmp/r-x

# R's launcher is a SHELL SCRIPT with the build prefix baked in:
#     R_HOME_DIR=/opt/R/<version>/lib/R
# and R deliberately IGNORES the R_HOME environment variable when it disagrees
# with that ("WARNING: ignoring environment value of R_HOME"). So the script has
# to be rewritten to the prefix this tarball installs to; R_HOME cannot simply
# be exported from env.sh the way JAVA_HOME can.
PREFIX="/opt/setup/$DIR"
old="/opt/R/$VERSION"
for f in "$ROOT"/bin/R "$ROOT"/bin/Rscript; do
  [ -f "$f" ] && sed -i "s|$old|$PREFIX|g" "$f"
done
echo "r: rewrote $old -> $PREFIX in bin/R and bin/Rscript"

"$ROOT/bin/R" --version | head -1

mkdir -p "$OUT"
ASSET="$OUT/r-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "r: wrote $ASSET"
