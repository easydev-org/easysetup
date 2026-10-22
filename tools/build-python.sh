#!/bin/bash
# build-python.sh <id> <version> <outdir>
#
# python-build-standalone "install_only" builds: a self-contained CPython with
# its own libpython and stdlib, so nothing is compiled here.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

ID="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$ID"
mkdir -p "$ROOT"

echo "python: $ID $VERSION - resolving"
ASSET_URL=$(
  curl -fsSL --retry 3 "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest" \
  | python3 -c '
import json,sys
want=sys.argv[1]
rel=json.load(sys.stdin)
for a in rel.get("assets",[]):
    n=a["name"]
    # install_only, not _stripped, not the debug/full variants.
    if n.startswith("cpython-"+want+"+") and n.endswith("-x86_64-unknown-linux-gnu-install_only.tar.gz"):
        print(a["browser_download_url"]); break
' "$VERSION"
)
[ -n "$ASSET_URL" ] || { echo "python: no install_only build for $VERSION" >&2; exit 1; }

echo "python: $ID $VERSION <- $ASSET_URL"
fetch "$ASSET_URL" /tmp/python.tar.gz
tar -xzf /tmp/python.tar.gz -C /tmp
cp -a /tmp/python/. "$ROOT"/
rm -rf /tmp/python /tmp/python.tar.gz

"$ROOT/bin/python3" --version

mkdir -p "$OUT"
ASSET="$OUT/python-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "python: wrote $ASSET"
