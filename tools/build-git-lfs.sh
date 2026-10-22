#!/bin/bash
# build-git-lfs.sh <dir> <version> <outdir>
# The tarball's root is git-lfs-<version>/, with the binary inside it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://github.com/git-lfs/git-lfs/releases/download/v${VERSION}/git-lfs-linux-amd64-v${VERSION}.tar.gz"
echo "git-lfs: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/lfs.tar.gz
rm -rf /tmp/lfs-x && mkdir -p /tmp/lfs-x
tar -xzf /tmp/lfs.tar.gz -C /tmp/lfs-x
rm -f /tmp/lfs.tar.gz

# Do not assume the layout: find the binary wherever it is.
bin=$(find /tmp/lfs-x -maxdepth 2 -type f -name git-lfs | head -1)
[ -n "$bin" ] || { echo "git-lfs: binary not in the tarball" >&2; find /tmp/lfs-x >&2; exit 1; }
cp -a "$bin" "$ROOT/bin/git-lfs"
chmod +x "$ROOT/bin/git-lfs"
rm -rf /tmp/lfs-x

"$ROOT/bin/git-lfs" --version

mkdir -p "$OUT"
ASSET="$OUT/git-lfs-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "git-lfs: wrote $ASSET"
