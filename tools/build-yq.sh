#!/bin/bash
# build-yq.sh <dir> <version> <outdir>
# The .tar.gz holds `./yq_linux_amd64` (plus a man page and an install script),
# so the binary is located and renamed rather than assumed to be ./yq.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://github.com/mikefarah/yq/releases/download/v${VERSION}/yq_linux_amd64.tar.gz"
echo "yq: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/yq.tar.gz
rm -rf /tmp/yq-x && mkdir -p /tmp/yq-x
tar -xzf /tmp/yq.tar.gz -C /tmp/yq-x
rm -f /tmp/yq.tar.gz
bin=$(find /tmp/yq-x -maxdepth 1 -type f -name 'yq_linux_amd64' | head -1)
[ -n "$bin" ] || { echo "yq: binary not in the tarball" >&2; ls /tmp/yq-x >&2; exit 1; }
cp -a "$bin" "$ROOT/bin/yq"
chmod +x "$ROOT/bin/yq"
rm -rf /tmp/yq-x

"$ROOT/bin/yq" --version

mkdir -p "$OUT"
ASSET="$OUT/yq-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "yq: wrote $ASSET"
