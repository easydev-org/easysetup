#!/bin/bash
# build-llvm.sh <dir> <version> <outdir>
#
# clang/LLVM from the official linux release, PRUNED.
#
# The full tarball is 1.9 GB compressed / 11.6 GB unpacked, and almost all of
# that is not a compiler: bin/ alone is 9 GB, led by flang (437 MB), mlir-opt
# (423 MB), mlir-rewrite (301 MB), bbc, llc, opt, and a 267 MB liblldb.
#
# What a build actually invokes is clang, lld and the binutils-style llvm tools.
# Measured on the real tarball, that set is ~650 MB of distinct binaries plus
# 101 MB of builtin headers, so this script keeps exactly that and nothing else.
#
# Two things worth knowing, both verified rather than assumed:
#
#   * clang-23 and clang-cpp are the SAME file (identical md5), as are
#     llvm-ar / llvm-ranlib / llvm-lib. They are kept once and hard-linked, or
#     the tree would be several hundred MB larger for no benefit.
#   * C++ needs the system's libstdc++ HEADERS (apt libstdc++-14-dev), not just
#     the library: `#include <iostream>` resolves from /usr/include/c++/<ver>.
#     That belongs in apt_deps, and the verify step compiles real C++ to prove
#     it works.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT/bin" "$ROOT/lib"

URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${VERSION}/LLVM-${VERSION}-Linux-X64.tar.xz"
echo "llvm: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/llvm.tar.xz

rm -rf /tmp/llvm-x && mkdir -p /tmp/llvm-x
tar -xJf /tmp/llvm.tar.xz -C /tmp/llvm-x
rm -f /tmp/llvm.tar.xz
SRC=$(find /tmp/llvm-x -maxdepth 1 -mindepth 1 -type d | head -1)
[ -n "$SRC" ] || { echo "llvm: unexpected tarball layout" >&2; exit 1; }

# --- the tools a build calls, plus the CI conveniences ---------------------
CORE="clang clang++ clang-23 clang-cpp clang-cl lld ld.lld lld-link wasm-ld \
llvm-ar llvm-ranlib llvm-nm llvm-objcopy llvm-objdump llvm-strip \
llvm-readelf llvm-config llvm-dlltool llvm-windres llvm-lib llvm-size \
llvm-strings clang-format"

for n in $CORE; do
  [ -e "$SRC/bin/$n" ] || continue
  # -L so a symlink becomes a real file we control; we re-create links below.
  cp -L "$SRC/bin/$n" "$ROOT/bin/$n"
  chmod +x "$ROOT/bin/$n"
done

# --- deduplicate the big duplicates ---------------------------------------
# clang, clang++, clang-cl and clang-cpp are byte-identical to clang-23;
# ld.lld / lld-link / wasm-ld are byte-identical to lld. Keep one copy and
# hard-link the rest, which keeps `clang++` and `-fuse-ld=lld` working.
dedupe() {
  local keep="$1"; shift
  [ -f "$ROOT/bin/$keep" ] || return 0
  local n
  for n in "$@"; do
    [ -f "$ROOT/bin/$n" ] || [ -e "$ROOT/bin/$n" ] || continue
    if [ "$n" != "$keep" ]; then
      rm -f "$ROOT/bin/$n"
      ln "$ROOT/bin/$keep" "$ROOT/bin/$n" 2>/dev/null || ln -s "$keep" "$ROOT/bin/$n"
    fi
  done
}
# Find whichever clang binary actually exists, then link the rest to it.
CLANG_REAL=""
for cand in clang-23 clang clang-cpp; do
  [ -f "$ROOT/bin/$cand" ] && { CLANG_REAL="$cand"; break; }
done
if [ -n "$CLANG_REAL" ]; then
  dedupe "$CLANG_REAL" clang clang++ clang-cl clang-cpp
fi
[ -f "$ROOT/bin/lld" ] && dedupe lld ld.lld lld-link wasm-ld
[ -f "$ROOT/bin/llvm-ar" ] && dedupe llvm-ar llvm-ranlib llvm-lib llvm-dlltool

# --- builtin headers: clang cannot compile without these -------------------
cp -a "$SRC/lib/clang" "$ROOT/lib/"
rm -rf /tmp/llvm-x

echo "llvm: kept $(ls "$ROOT/bin" | wc -l) tool(s), tree is $(du -sh "$ROOT" | cut -f1)"

# --- prove it compiles and links, which is the whole point ----------------
"$ROOT/bin/clang" --version | head -1
printf '#include <stdio.h>\n#include <stddef.h>\nint main(void){printf("c ok %%zu\\n",sizeof(size_t));return 0;}\n' > /tmp/llvm-t.c
"$ROOT/bin/clang" -O1 /tmp/llvm-t.c -o /tmp/llvm-t-c
/tmp/llvm-t-c
"$ROOT/bin/clang" -fuse-ld=lld -O1 /tmp/llvm-t.c -o /tmp/llvm-t-lld
/tmp/llvm-t-lld
rm -f /tmp/llvm-t.c /tmp/llvm-t-c /tmp/llvm-t-lld

mkdir -p "$OUT"
ASSET="$OUT/llvm-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "llvm: wrote $ASSET ($(du -h "$ASSET" | cut -f1))"
