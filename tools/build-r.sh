#!/bin/bash
# build-r.sh <dir> <version> <outdir>
#
# Posit publishes prebuilt R as a .deb per ubuntu release. A .deb is an ar
# archive containing a data tarball, so the build EXTRACTS it into our prefix
# with `dpkg-deb -x` rather than installing it onto the build host.
#
# /usr/lib/R/bin/R is where a deb-installed R lands, so the tree keeps that
# layout and the verify step calls it by that path.
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

# The deb's payload is /usr/lib/R plus /usr/bin/R symlinks; keep it under our
# own prefix so nothing is written to the host.
cp -a /tmp/r-x/usr/. "$ROOT"/
rm -rf /tmp/r-x

"$ROOT/lib/R/bin/R" --version | head -1

mkdir -p "$OUT"
ASSET="$OUT/r-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "r: wrote $ASSET"
