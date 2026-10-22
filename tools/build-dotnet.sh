#!/bin/bash
# build-dotnet.sh <dir> <version> <outdir>
#
# .NET SDK from Microsoft's official tarball. dotnet needs ICU for
# globalization, which is in apt_deps rather than bundled.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

CHANNEL="${VERSION%%.*}"          # 10.0.402 -> 10
URL="https://builds.dotnet.microsoft.com/dotnet/Sdk/${VERSION}/dotnet-sdk-${VERSION}-linux-x64.tar.gz"
echo "dotnet: $DIR $VERSION (channel $CHANNEL) <- $URL"
fetch "$URL" /tmp/dotnet.tar.gz
tar -xzf /tmp/dotnet.tar.gz -C "$ROOT"
rm -f /tmp/dotnet.tar.gz

# The SDK writes to DOTNET_CLI_HOME on first run; point it inside the tree so
# the build never touches $HOME of the build container.
export DOTNET_CLI_HOME="$ROOT/.cli-home"
export DOTNET_NOLOGO=1
"$ROOT/dotnet" --info 2>&1 | grep -E '^ Version|^ SDK' | head -2
"$ROOT/dotnet" --version

mkdir -p "$OUT"
ASSET="$OUT/dotnet-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "dotnet: wrote $ASSET"
