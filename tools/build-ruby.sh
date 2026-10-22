#!/bin/bash
# build-ruby.sh <dir> <version> <outdir>
#
# Ruby publishes SOURCE tarballs only, so this is the one build that compiles.
# It runs here, once, in the release job; the tarball it produces is the
# compiled tree, so `install.sh` only ever unpacks.
#
# --disable-install-doc keeps the tree ~40 MB smaller and docs are not needed by
# a CI job. --enable-shared links libyaml/openssl dynamically, which is why the
# apt_deps list exists.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
MINOR="${VERSION%.*}"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://cache.ruby-lang.org/pub/ruby/${MINOR}/ruby-${VERSION}.tar.gz"
echo "ruby: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/ruby.tar.gz

rm -rf /tmp/ruby-src && mkdir -p /tmp/ruby-src
tar -xzf /tmp/ruby.tar.gz -C /tmp/ruby-src --strip-components=1
rm -f /tmp/ruby.tar.gz

cd /tmp/ruby-src
./configure --prefix="$ROOT" --disable-install-doc --enable-shared \
  2>&1 | tail -3
make -j"$(nproc)" 2>&1 | tail -3
make install 2>&1 | tail -3
cd /
rm -rf /tmp/ruby-src

"$ROOT/bin/ruby" --version
"$ROOT/bin/gem" --version

mkdir -p "$OUT"
ASSET="$OUT/ruby-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "ruby: wrote $ASSET"
