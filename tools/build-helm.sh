#!/bin/bash
# build-helm.sh <dir> <version> <outdir>
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://get.helm.sh/helm-v${VERSION}-linux-amd64.tar.gz"
echo "helm: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/helm.tar.gz
rm -rf /tmp/helm-x && mkdir -p /tmp/helm-x
tar -xzf /tmp/helm.tar.gz -C /tmp/helm-x
# The archive holds linux-amd64/helm; keep the layout /opt/setup/<dir>/bin/helm.
mkdir -p "$ROOT/bin"
cp /tmp/helm-x/linux-amd64/helm "$ROOT/bin/helm"
chmod +x "$ROOT/bin/helm"
rm -rf /tmp/helm.tar.gz /tmp/helm-x

"$ROOT/bin/helm" version --short

mkdir -p "$OUT"
ASSET="$OUT/helm-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "helm: wrote $ASSET"
