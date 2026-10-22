#!/bin/bash
# build-php.sh <dir> <version> <outdir>
#
# PHP from shivammathur/php-builder, which publishes a **debian 13 (= trixie)**
# build - an exact platform match. Nothing is compiled.
#
# The tarball is a debian filesystem tree, not a relocatable prefix:
#
#   ./usr/bin/php8.5          the CLI (versioned name, like debian's own package)
#   ./usr/bin/php-config8.5   for building extensions
#   ./usr/bin/phpize8.5
#   ./usr/lib/php/...         extensions and their ini files
#   ./etc/php/8.5/...         ini + conf.d
#
# So the build re-roots that tree under /opt/setup/<dir>/ and creates the
# unversioned `php` symlink a CI script expects. Everything ends up inside our
# directory: nothing is written to /usr on the consumer.
#
# NOTE on `version`: php-builder tags a RELEASE LINE ("8.5"), not a patch level.
# matrix.yml pins that tag, and the exact patch release is whatever the tag
# currently ships. One readable pin, and our own asset is checksummed, so a
# rebuild is still verified.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
SHORT="${VERSION}"                 # 8.5

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://github.com/shivammathur/php-builder/releases/download/${VERSION}/php_${VERSION}+debian13.tar.xz"
echo "php: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/php.tar.xz

rm -rf /tmp/php-x && mkdir -p /tmp/php-x
tar -xJf /tmp/php.tar.xz -C /tmp/php-x
rm -f /tmp/php.tar.xz

# Re-root: the tree is ./usr, ./etc, ... so copy each top dir under $ROOT.
for d in usr etc; do
  [ -d "/tmp/php-x/$d" ] && cp -a "/tmp/php-x/$d" "$ROOT/"
done
rm -rf /tmp/php-x

# The CLI is versioned (usr/bin/php8.5). Provide the unversioned names a build
# script actually calls, plus phpize/php-config which keep their versioned names
# in debian and are needed to build extensions.
ln -sf "php${SHORT}" "$ROOT/bin/php"
ln -sf "php-config${SHORT}" "$ROOT/bin/php-config"
ln -sf "phpize${SHORT}" "$ROOT/bin/phpize"

# php was built for the debian prefix (/usr), so tell it where its ini and
# extension dir really are now. PHPRC + PHP_INI_SCAN_DIR are the supported way;
# they are also exported from env.sh produced by install.sh.
export PHPRC="$ROOT/etc/php/${SHORT}/cli"
export PHP_INI_SCAN_DIR="$ROOT/etc/php/${SHORT}/cli/conf.d:$ROOT/etc/php/${SHORT}/mods-available"

"$ROOT/bin/php" --version | head -1
"$ROOT/bin/php" -r 'echo "openssl=", extension_loaded("openssl") ? "yes" : "NO", " json=", extension_loaded("json") ? "yes" : "NO", "\n";'

mkdir -p "$OUT"
ASSET="$OUT/php-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "php: wrote $ASSET"
