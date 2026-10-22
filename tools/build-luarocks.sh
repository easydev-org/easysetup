#!/bin/bash
# build-luarocks.sh <dir> <version> <outdir>
# luarocks is a lua script plus libs; it needs a lua interpreter, which the
# entry declares via `requires`. The official linux zip is a prebuilt tree.
#
# The zip is FLAT: it contains only
#   luarocks-<ver>-linux-x86_64/luarocks
#   luarocks-<ver>-linux-x86_64/luarocks-admin
# with no bin/ and no lua modules, so those two go into bin/ ourselves.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://github.com/luarocks/luarocks/releases/download/v${VERSION}/luarocks-${VERSION}-linux-x86_64.zip"
echo "luarocks: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/luarocks.zip
unzip -q -o /tmp/luarocks.zip -d /tmp/luarocks-x
SRC=/tmp/luarocks-x/luarocks-"${VERSION}"-linux-x86_64
test -d "$SRC" || { echo "luarocks: unexpected zip layout" >&2; ls /tmp/luarocks-x >&2; exit 1; }
mkdir -p "$ROOT/bin"
cp -a "$SRC"/luarocks "$SRC"/luarocks-admin "$ROOT/bin/" 2>/dev/null || \
  cp -a "$SRC"/. "$ROOT/bin/"
chmod +x "$ROOT"/bin/luarocks*
rm -rf /tmp/luarocks.zip /tmp/luarocks-x

test -x "$ROOT/bin/luarocks" || { echo "luarocks: bin/luarocks missing" >&2; exit 1; }
echo "luarocks: bin/luarocks present (lua comes from requires)"

mkdir -p "$OUT"
ASSET="$OUT/luarocks-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "luarocks: wrote $ASSET"
