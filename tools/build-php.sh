#!/bin/bash
# build-php.sh <dir> <version> <outdir>
#
# PHP from shivammathur/php-builder — the prebuilt tarball behind GitHub
# Actions' setup-php, and it publishes a **debian 13 (= trixie)** build, so it
# is an exact platform match. Nothing is compiled.
#
# NOTE on `version`: php-builder tags a RELEASE LINE ("8.5"), not a patch level.
# The version in matrix.yml is therefore the builder tag, and the exact patch
# release is whatever that tag currently ships. That is deliberate: tying to the
# tag means the pin is one readable value, and a rebuild of the same tag is
# still reproducible because our own release asset is checksummed.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://github.com/shivammathur/php-builder/releases/download/${VERSION}/php_${VERSION}+debian13.tar.xz"
echo "php: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/php.tar.xz

# The tarball is a filesystem tree rooted at usr/ (it is meant to be unpacked
# over /). Unpack it into a scratch prefix, then take the parts a CLI needs.
rm -rf /tmp/php-x && mkdir -p /tmp/php-x
tar -xJf /tmp/php.tar.xz -C /tmp/php-x
rm -f /tmp/php.tar.xz

echo "php: layout:"
ls /tmp/php-x | head

# Copy the whole usr/local tree it ships (bin/sbin/lib/etc) so php.ini and its
# extensions stay together under our own directory.
if [ -d /tmp/php-x/usr/local ]; then
  cp -a /tmp/php-x/usr/local/. "$ROOT"/
else
  cp -a /tmp/php-x/. "$ROOT"/
fi
rm -rf /tmp/php-x

# php resolves its ini and extension dir from the compiled-in prefix, which was
# /usr/local. Point it at this tree so nothing leaks to the host.
export PHPRC="$ROOT/lib"
"$ROOT/bin/php" --version | head -1
"$ROOT/bin/php" -r 'echo "openssl=", extension_loaded("openssl") ? "yes" : "NO", " json=", extension_loaded("json") ? "yes" : "NO", "\n";'

mkdir -p "$OUT"
ASSET="$OUT/php-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "php: wrote $ASSET"
