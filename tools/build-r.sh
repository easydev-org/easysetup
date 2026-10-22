#!/bin/bash
# build-r.sh <dir> <version> <outdir>
#
# R from Posit's prebuilt ubuntu-24.04 .deb, PLUS the two libraries whose ABI
# trixie does not provide.
#
# The .deb links against libicuuc.so.74 / libicui18n.so.74 and libjpeg.so.8.
# trixie ships libicu 76 and libjpeg .so.62 - different sonames, not different
# patch levels, so apt_deps cannot satisfy them and the binary cannot start.
#
# `bundled_libs` downloads the distro packages that DO carry those exact
# sonames and unpacks them into the tree's own lib/, which env.sh puts on
# LD_LIBRARY_PATH. Still only apt + unpack: nothing is compiled, and the
# consumer needs no extra apt packages for these.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://cdn.posit.co/r/ubuntu-2404/pkgs/r-${VERSION}_1_amd64.deb"
echo "r: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/r.deb
dpkg-deb -x /tmp/r.deb /tmp/r-x
rm -f /tmp/r.deb

SRC=$(find /tmp/r-x -maxdepth 4 -type d -name "$VERSION" -path "*/opt/R/*" | head -1)
[ -n "$SRC" ] || { echo "r: no opt/R/<version> in the .deb" >&2; exit 1; }
cp -a "$SRC"/. "$ROOT"/
rm -rf /tmp/r-x

# R's launcher is a shell script with the build prefix baked in, and R IGNORES
# $R_HOME when it disagrees ("WARNING: ignoring environment value of R_HOME"),
# so the script itself has to name the final prefix.
PREFIX="/opt/setup/$DIR"
old="/opt/R/$VERSION"
for f in "$ROOT"/bin/R "$ROOT"/bin/Rscript; do
  [ -f "$f" ] && sed -i "s|$old|$PREFIX|g" "$f"
done
echo "r: rewrote $old -> $PREFIX"

# --- bundled libraries -----------------------------------------------------
# Each entry is a .deb whose payload carries a soname trixie does not ship.
# They land in lib/bundled/ and are found through LD_LIBRARY_PATH.
mkdir -p "$ROOT/lib/bundled"
bundle_deb() {
  local url="$1" name="$2"
  echo "r: bundling $name"
  fetch "$url" /tmp/bundle.deb
  dpkg-deb -x /tmp/bundle.deb /tmp/bundle-x
  # Library payloads live under usr/lib/<triplet>/; flatten just the .so files.
  find /tmp/bundle-x -name '*.so.*' -o -name '*.so' | while read -r so; do
    cp -a "$so" "$ROOT/lib/bundled/"
  done
  rm -rf /tmp/bundle.deb /tmp/bundle-x
}

# libicu74: exact soname libicuuc.so.74 / libicui18n.so.74 / libicudata.so.74.
bundle_deb \
  "http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu74_74.2-1ubuntu3.1_amd64.deb" \
  "libicu74"
# libjpeg-turbo8: provides libjpeg.so.8 (trixie's libjpeg62-turbo provides .so.62).
bundle_deb \
  "http://archive.ubuntu.com/ubuntu/pool/main/libj/libjpeg-turbo/libjpeg-turbo8_2.1.5-2ubuntu2_amd64.deb" \
  "libjpeg-turbo8"

ls "$ROOT/lib/bundled" | head -10

# Verify against the FINAL path: bin/R names it, so the staged tree cannot be
# used directly. A symlink stands in for the install location during the check.
mkdir -p "$(dirname "$PREFIX")"
rm -f "$PREFIX"
ln -s "$ROOT" "$PREFIX"
LD_LIBRARY_PATH="$ROOT/lib/bundled${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$PREFIX/bin/R" --version | head -1
rm -f "$PREFIX"

mkdir -p "$OUT"
ASSET="$OUT/r-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "r: wrote $ASSET"
