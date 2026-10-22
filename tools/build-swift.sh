#!/bin/bash
# build-swift.sh <dir> <version> <outdir>
#
# Swift toolchain from swift.org's own debian13 build - a native trixie target,
# so unlike R there is no foreign-ABI problem to work around: it links trixie's
# libicu76 and friends directly.
#
# The tarball's root is swift-<ver>-RELEASE-debian13/usr/, so strip two
# components and the tree lands as /opt/setup/swift-<ver>/{bin,lib,...}.
#
# The runtime dependencies are exactly the list swift.org publishes for Debian
# 13 (install/linux/tarball), minus the -dev packages: this is a runtime
# toolchain, not a build-from-source environment.
set -euo pipefail

. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-relocate.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://download.swift.org/swift-${VERSION}-release/debian13/swift-${VERSION}-RELEASE/swift-${VERSION}-RELEASE-debian13.tar.gz"
echo "swift: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/swift.tar.gz

rm -rf /tmp/swift-x && mkdir -p /tmp/swift-x
tar -xzf /tmp/swift.tar.gz -C /tmp/swift-x
rm -f /tmp/swift.tar.gz

# Root is swift-<ver>-RELEASE-debian13/; take its usr/ as the prefix.
SRC=$(find /tmp/swift-x -maxdepth 2 -type d -name usr | head -1)
[ -n "$SRC" ] || { echo "swift: no usr/ in the tarball" >&2; ls /tmp/swift-x >&2; exit 1; }
cp -a "$SRC"/. "$ROOT"/
rm -rf /tmp/swift-x

# The toolchain records its own prefix in a few places (notably
# lib/swift/{linux,}/*.swiftmodule search paths and bin/*.cfg). Repoint them.
n=$(relocate_scripts "$ROOT" "/opt/setup/$DIR")
echo "swift: rewrote the prefix in $n script(s)"

# Verify through the FINAL path, as the consumer will see it.
PREFIX="/opt/setup/$DIR"
mkdir -p "$(dirname "$PREFIX")"
rm -f "$PREFIX"
ln -s "$ROOT" "$PREFIX"
"$PREFIX/bin/swift" --version
rm -f "$PREFIX"

mkdir -p "$OUT"
ASSET="$OUT/swift-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "swift: wrote $ASSET"
