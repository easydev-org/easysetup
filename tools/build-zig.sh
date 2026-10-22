#!/bin/bash
# build-zig.sh <dir> <version> <outdir>
#
# Zig ships one relocatable tree (zig-x86_64-linux-<ver>/) with the compiler,
# lib/ and the C/C++ headers it carries. `zig cc` turns it into a C/C++
# compiler, which is why this is the cheap route to native builds: 55 MB
# instead of LLVM's 1.9 GB.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://ziglang.org/download/${VERSION}/zig-x86_64-linux-${VERSION}.tar.xz"
echo "zig: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/zig.tar.xz
tar -xJf /tmp/zig.tar.xz -C "$ROOT" --strip-components=1
rm -f /tmp/zig.tar.xz

# zig resolves its lib/ relative to the binary, so no rewriting is needed - but
# verify that, rather than assuming.
"$ROOT/zig" version
test -d "$ROOT/lib" || { echo "zig: lib/ missing" >&2; exit 1; }

mkdir -p "$OUT"
ASSET="$OUT/zig-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "zig: wrote $ASSET"
