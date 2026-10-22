#!/bin/bash
# build-bazel.sh <dir> <version> <outdir>
#
# Bazel from the official installer .sh. Installing it means running the
# installer against a prefix; it extracts the embedded zip, so this is a
# unpack, not a build. Bazel itself is a Java program, which is why a JRE is in
# apt_deps.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://github.com/bazelbuild/bazel/releases/download/${VERSION}/bazel-${VERSION}-installer-linux-x86_64.sh"
echo "bazel: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/bazel.sh
chmod +x /tmp/bazel.sh

# The installer's prefix must exist and be absolute.
/tmp/bazel.sh --prefix="$ROOT" 2>&1 | tail -3
rm -f /tmp/bazel.sh

mkdir -p "$ROOT/bin"
ln -sf "$ROOT/bin/bazel-real" "$ROOT/bin/bazel-real-real" 2>/dev/null || true
"$ROOT/bin/bazel" --version 2>&1 | head -1 \
  || { echo "bazel: --version failed" >&2; exit 1; }

mkdir -p "$OUT"
ASSET="$OUT/bazel-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "bazel: wrote $ASSET"
