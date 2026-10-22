#!/bin/bash
# build-ghc.sh <dir> <version> <outdir>
#
# GHC publishes per-debian-release builds; there is no deb13 tarball, so the
# deb12 build is used - glibc is backward compatible, so it runs on trixie.
# GHC's tarball is a bindist: its own ./configure + make install is how you lay
# it out, and that is an unpack of prebuilt binaries, not a compiler build.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-relocate.sh"

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

# GHC's bin/ghc is a WRAPPER SCRIPT recording the install prefix it saw at
# configure time (a /tmp staging dir here). Once packed and unpacked elsewhere
# it looks for lib/ghc-<ver>/bin/ghc-<ver> under that dead path and fails.
n=$(relocate_scripts "$ROOT" "/opt/setup/$DIR")
echo "ghc: rewrote the prefix in $n wrapper script(s)"

# Verify through the FINAL path: bin/ghc now hard-codes it (it looks for
# lib/ghc-<ver>/bin/ghc-<ver> under /opt/setup/<dir>), and the tree is still
# staged under /tmp. A symlink stands in for the install location.
PREFIX="/opt/setup/$DIR"
mkdir -p "$(dirname "$PREFIX")"
rm -f "$PREFIX"
ln -s "$ROOT" "$PREFIX"
"$PREFIX/bin/ghc" --version
rm -f "$PREFIX"

mkdir -p "$OUT"
ASSET="$OUT/ghc-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "ghc: wrote $ASSET"
