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

# Verify the PAYLOAD, do not execute it.
#
# Two reasons the binary is not run here:
#   * `dotnet --version` needs ICU (globalization) and tzdata, which are in
#     apt_deps and therefore present in the release container but not in every
#     build sandbox - running it there aborted with a TimeZoneInfo crash for a
#     perfectly good SDK;
#   * an earlier `dotnet --info | grep ...` also killed the build, because grep
#     returns 1 on no match and `set -o pipefail` turns that into a failure.
#
# Structure is what this script has to guarantee; the release workflow runs the
# tool once, inside debian:trixie with the right libraries installed.
test -x "$ROOT/dotnet" || { echo "dotnet: binary missing" >&2; exit 1; }
ls "$ROOT"/sdk/*/dotnet.dll >/dev/null 2>&1 || {
  echo "dotnet: no SDK directory in the tarball" >&2; exit 1; }
echo "dotnet: SDK $(ls "$ROOT"/sdk | head -1) present ($(du -sh "$ROOT" | cut -f1))"

mkdir -p "$OUT"
ASSET="$OUT/dotnet-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "dotnet: wrote $ASSET"
