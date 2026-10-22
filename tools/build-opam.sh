#!/bin/bash
# build-opam.sh <dir> <version> <outdir>
# opam is a single static binary published on GitHub releases.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT/bin"

URL="https://github.com/ocaml/opam/releases/download/${VERSION}/opam-${VERSION}-x86_64-linux"
echo "opam: $DIR $VERSION <- $URL"
fetch "$URL" "$ROOT/bin/opam"
chmod +x "$ROOT/bin/opam"

"$ROOT/bin/opam" --version

mkdir -p "$OUT"
ASSET="$OUT/opam-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "opam: wrote $ASSET"
