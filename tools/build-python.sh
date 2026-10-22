#!/bin/bash
# build-python.sh <version> <outdir> — pack a standalone CPython into a tarball.
#
# python-build-standalone publishes "install_only" builds: a self-contained
# CPython with its own libpython and stdlib, so nothing has to be compiled here.
set -euo pipefail

VERSION="$1"
OUT="$2"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/python"
mkdir -p "$ROOT"

# The release tag is a date; the asset name carries the cpython version. Find the
# newest matching asset so a version bump is a one-line edit in matrix.yml.
echo "python: resolving ${VERSION}"
ASSET_URL=$(
  curl -fsSL --retry 3 "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest" \
  | python3 -c '
import json,sys
want=sys.argv[1]
rel=json.load(sys.stdin)
for a in rel.get("assets",[]):
    n=a["name"]
    if n.startswith("cpython-"+want+"+") and n.endswith("-x86_64-unknown-linux-gnu-install_only.tar.gz"):
        print(a["browser_download_url"]); break
' "$VERSION"
)
[ -n "$ASSET_URL" ] || { echo "python: no install_only build for $VERSION" >&2; exit 1; }

echo "python: ${VERSION} <- ${ASSET_URL}"
curl -fsSL --retry 3 -o /tmp/python.tar.gz "$ASSET_URL"
tar -xzf /tmp/python.tar.gz -C /tmp
cp -a /tmp/python/. "$ROOT"/
rm -rf /tmp/python /tmp/python.tar.gz

"$ROOT/bin/python3" --version

mkdir -p "$OUT"
ASSET="$OUT/python-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "python: wrote $ASSET"
