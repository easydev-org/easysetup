#!/bin/bash
# build-julia.sh <dir> <version> <outdir>
# Julia's tarball's root is julia-<version>/, so strip one component.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

MINOR="${VERSION%.*}"
URL="https://julialang-s3.julialang.org/bin/linux/x64/${MINOR}/julia-${VERSION}-linux-x86_64.tar.gz"
echo "julia: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/julia.tar.gz
tar -xzf /tmp/julia.tar.gz -C "$ROOT" --strip-components=1
rm -f /tmp/julia.tar.gz

"$ROOT/bin/julia" --version

mkdir -p "$OUT"
ASSET="$OUT/julia-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "julia: wrote $ASSET"
