#!/bin/bash
# build-ghc.sh <dir> <version> <outdir>
#
# GHC publishes per-debian-release builds; there is no deb13 tarball, so the
# deb12 build is used - glibc is backward compatible, so it runs on trixie.
# GHC's tarball is a bindist: its own ./configure + make install is how you lay
# it out, and that is an unpack of prebuilt binaries, not a compiler build.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://downloads.haskell.org/~ghc/${VERSION}/ghc-${VERSION}-x86_64-deb12-linux.tar.xz"
echo "ghc: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/ghc.tar.xz
rm -rf /tmp/ghc-src && mkdir -p /tmp/ghc-src
tar -xJf /tmp/ghc.tar.xz -C /tmp/ghc-src --strip-components=1
rm -f /tmp/ghc.tar.xz

cd /tmp/ghc-src
./configure --prefix="$ROOT" 2>&1 | tail -2
make install 2>&1 | tail -2
cd /
rm -rf /tmp/ghc-src

"$ROOT/bin/ghc" --version

mkdir -p "$OUT"
ASSET="$OUT/ghc-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "ghc: wrote $ASSET"
