#!/bin/bash
# build-php.sh <dir> <version> <outdir>
#
# PHP built from source. php.net publishes source only, and the CLI needs to be
# configured with the extensions a CI job expects (openssl, curl, mbstring,
# pdo_sqlite) - a bare ./configure would produce a php that cannot reach https.
#
# This compiles once here; the tarball is the built tree, so installing is an
# unpack.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
MAJOR_MINOR="${VERSION%.*}"       # 8.5.12 -> 8.5

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://www.php.net/distributions/php-${VERSION}.tar.gz"
echo "php: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/php.tar.gz
rm -rf /tmp/php-src && mkdir -p /tmp/php-src
tar -xzf /tmp/php.tar.gz -C /tmp/php-src --strip-components=1
rm -f /tmp/php.tar.gz

cd /tmp/php-src
./configure --prefix="$ROOT" \
  --enable-mbstring --with-openssl --with-curl --with-zlib \
  --enable-pdo --with-pdo-sqlite --without-pear \
  2>&1 | tail -3
make -j"$(nproc)" 2>&1 | tail -3
make install 2>&1 | tail -3
cd /
rm -rf /tmp/php-src

"$ROOT/bin/php" --version | head -1
"$ROOT/bin/php" -r 'echo extension_loaded("openssl") ? "openssl ok\n" : "openssl MISSING\n";'

mkdir -p "$OUT"
ASSET="$OUT/php-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "php: wrote $ASSET"
