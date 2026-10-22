#!/bin/bash
# build-elixir.sh <dir> <version> <outdir>
# Elixir's precompiled zip is BEAM bytecode: it needs an erlang runtime, which
# the entry declares via `requires`. Nothing is compiled here.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

# The zip name records which OTP it targets. Pick the OTP major that the
# `requires` erlang entry provides, defaulting to the newest published.
OTP="${ELIXIR_OTP:-29}"

STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"
URL="https://github.com/elixir-lang/elixir/releases/download/v${VERSION}/elixir-otp-${OTP}.zip"
echo "elixir: $DIR $VERSION (otp $OTP) <- $URL"
fetch "$URL" /tmp/elixir.zip
unzip -q -o /tmp/elixir.zip -d "$ROOT"
rm -f /tmp/elixir.zip

# The zip's root is the elixir tree itself (bin/, lib/).
test -x "$ROOT/bin/elixir" || { echo "elixir: bin/elixir missing" >&2; exit 1; }
echo "elixir: bin/elixir + lib present (erlang comes from requires)"

mkdir -p "$OUT"
ASSET="$OUT/elixir-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "elixir: wrote $ASSET"
