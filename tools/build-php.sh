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

# This tarball is debian's FULL php packaging: CLI, php-fpm, the apache2 module
# and every bundled extension. Taken whole it needs ~40 shared libraries
# (libnetsnmp, librdkafka, libzmq, libpq, libtidy, ...), which is not what a CI
# job wants and not something apt_deps should be asked to satisfy.
#
# So only the CLI is kept: bin/php*/php-config*/phpize*, the shared libs those
# need, and the two ini directories the CLI reads. php-fpm and the apache module
# are dropped along with their extension set - a CI job runs `php script.php`,
# not a web server.
mkdir -p "$ROOT/bin"
for f in /tmp/php-x/usr/bin/php"${SHORT}" \
         /tmp/php-x/usr/bin/php-config"${SHORT}" \
         /tmp/php-x/usr/bin/phpize"${SHORT}"; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    php-fpm*|php-cgi*|phpdbg*) continue ;;   # server/debug SAPI: not needed
  esac
  cp -a "$f" "$ROOT/bin/"
done

# The CLI's own libraries (it links libphp only when built as a module; the CLI
# binary is self-contained apart from the extension .so files below).
[ -d /tmp/php-x/usr/lib/php ] && cp -a /tmp/php-x/usr/lib "$ROOT/"

# Only the ini that configures the CLI.
mkdir -p "$ROOT/etc/php/${SHORT}/cli"
if [ -d "/tmp/php-x/etc/php/${SHORT}/cli" ]; then
  cp -a "/tmp/php-x/etc/php/${SHORT}/cli/." "$ROOT/etc/php/${SHORT}/cli/"
fi
if [ -d "/tmp/php-x/etc/php/${SHORT}/mods-available" ]; then
  mkdir -p "$ROOT/etc/php/${SHORT}/mods-available"
  cp -a "/tmp/php-x/etc/php/${SHORT}/mods-available/." "$ROOT/etc/php/${SHORT}/mods-available/"
fi
rm -rf /tmp/php-x

# The CLI is versioned (bin/php8.5, from debian's packaging). Provide the
# unversioned names a build script actually calls.
ln -sf "php${SHORT}" "$ROOT/bin/php"
[ -e "$ROOT/bin/php-config${SHORT}" ] && ln -sf "php-config${SHORT}" "$ROOT/bin/php-config"
[ -e "$ROOT/bin/phpize${SHORT}" ] && ln -sf "phpize${SHORT}" "$ROOT/bin/phpize"

# php was built for the debian prefix (/usr), so tell it where its ini and
# extension dir really are now. PHPRC + PHP_INI_SCAN_DIR are the supported way;
# they are also exported from env.sh produced by install.sh.
export PHPRC="$ROOT/etc/php/${SHORT}/cli"
export PHP_INI_SCAN_DIR="$ROOT/etc/php/${SHORT}/cli/conf.d:$ROOT/etc/php/${SHORT}/mods-available"

"$ROOT/bin/php" --version | head -1 \
  || { echo "php: --version failed" >&2; exit 1; }
"$ROOT/bin/php" -r 'echo "openssl=", extension_loaded("openssl") ? "yes" : "NO", " json=", extension_loaded("json") ? "yes" : "NO", "\n";'

mkdir -p "$OUT"
ASSET="$OUT/php-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "php: wrote $ASSET"
