#!/bin/bash
# build-lua.sh <dir> <version> <outdir>
# Lua has no official binary release, so it is built from source here. It is
# tiny (a few seconds) and the result is a plain interpreter under the prefix.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://www.lua.org/ftp/lua-${VERSION}.tar.gz"
echo "lua: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/lua.tar.gz
rm -rf /tmp/lua-src && mkdir -p /tmp/lua-src
tar -xzf /tmp/lua.tar.gz -C /tmp/lua-src --strip-components=1
rm -f /tmp/lua.tar.gz

cd /tmp/lua-src
make linux MYCFLAGS="-fPIC" 2>&1 | tail -2
make install INSTALL_TOP="$ROOT" 2>&1 | tail -2
cd /
rm -rf /tmp/lua-src

"$ROOT/bin/lua" -v 2>&1 | head -1

mkdir -p "$OUT"
ASSET="$OUT/lua-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "lua: wrote $ASSET"
