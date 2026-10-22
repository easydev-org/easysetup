#!/bin/bash
# build-conda.sh <dir> <version> <outdir>
# Miniforge: its installer is a shell script that surfaces a payload; running it
# with -b -p <prefix> unpacks a complete conda into that prefix without touching
# the host and without running conda's own post-install steps against it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
# Do NOT create $ROOT first: miniforge's -p refuses an existing directory
# ("ERROR: File or directory already exists"). The parent must exist, the target
# must not.
mkdir -p "$(dirname "$ROOT")"

URL="https://github.com/conda-forge/miniforge/releases/download/${VERSION}/Miniforge3-${VERSION}-Linux-x86_64.sh"
echo "conda: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/miniforge.sh
chmod +x /tmp/miniforge.sh

# -b batch, -p prefix: unpacks into $ROOT with no prompts and no shell rc edits.
bash /tmp/miniforge.sh -b -p "$ROOT" 2>&1 | tail -3
rm -f /tmp/miniforge.sh

# Miniforge writes ABSOLUTE paths into the tree: the `conda` entrypoint is a
# script whose shebang points at the prefix it was installed to (a /tmp staging
# path here). Rewrite every such script to the prefix this tarball will live at,
# exactly as build-ruby does - otherwise `conda` fails with
# "cannot execute: required file not found" once the tree moves.
PREFIX="/opt/setup/$DIR"
fixed=0
for f in "$ROOT"/bin/* "$ROOT"/condabin/*; do
  [ -f "$f" ] || continue
  head -c 2 "$f" 2>/dev/null | grep -q '#!' || continue
  if head -1 "$f" | grep -q "$ROOT"; then
    # The interpreter is bin/python3; there is no `python` in a miniforge root.
    sed -i "1s|.*|#!$PREFIX/bin/python3|" "$f"
    fixed=$((fixed + 1))
  fi
done
echo "conda: rewrote $fixed shebang(s) to $PREFIX"

# Run it the way a consumer will. The rewritten shebang names $PREFIX, which
# does not exist during the build, so call through the interpreter here.
"$ROOT/bin/python3" "$ROOT/bin/conda" --version

mkdir -p "$OUT"
ASSET="$OUT/conda-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "conda: wrote $ASSET"
