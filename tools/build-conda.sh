#!/bin/bash
# build-conda.sh <dir> <version> <outdir>
# Miniforge: its installer is a shell script that surfaces a payload; running it
# with -b -p <prefix> unpacks a complete conda into that prefix without touching
# the host and without running conda's own post-install steps against it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://github.com/conda-forge/miniforge/releases/download/${VERSION}/Miniforge3-${VERSION}-Linux-x86_64.sh"
echo "conda: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/miniforge.sh
chmod +x /tmp/miniforge.sh

# -b batch, -p prefix: unpacks into $ROOT with no prompts and no shell rc edits.
bash /tmp/miniforge.sh -b -p "$ROOT" 2>&1 | tail -3
rm -f /tmp/miniforge.sh

"$ROOT/bin/conda" --version

mkdir -p "$OUT"
ASSET="$OUT/conda-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "conda: wrote $ASSET"
