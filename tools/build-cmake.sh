#!/bin/bash
# build-cmake.sh <dir> <version> <outdir>
# CMake ships a relocatable tarball whose root is cmake-<version>-linux-x86_64/.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-relocate.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://github.com/Kitware/CMake/releases/download/v${VERSION}/cmake-${VERSION}-linux-x86_64.tar.gz"
echo "cmake: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/cmake.tar.gz
tar -xzf /tmp/cmake.tar.gz -C "$ROOT" --strip-components=1
rm -f /tmp/cmake.tar.gz

# Any wrapper script that recorded the build prefix gets repointed.
n=$(relocate_scripts "$ROOT" "/opt/setup/$DIR")
echo "cmake: rewrote the prefix in $n script(s)"

CMAKE_ROOT="$ROOT/share/cmake-$VERSION" "$ROOT/bin/cmake" --version | head -1

mkdir -p "$OUT"
ASSET="$OUT/cmake-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "cmake: wrote $ASSET"
