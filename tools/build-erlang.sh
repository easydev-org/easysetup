#!/bin/bash
# build-erlang.sh <dir> <version> <outdir>
#
# Prebuilt OTP from builds.hex.pm — the same binaries Hex's `bob` installs.
# NOT erlef/otp_builds: those OTP-29.* releases carry only macOS assets, and
# their rolling `maint-latest` tag is from 2024 and still OTP 27. builds.hex.pm
# actually publishes linux builds for current OTP (29.1.2 verified).
#
# The tarball is an UNINSTALLED tree: it contains ./Install and a erts-*/ dir.
# `./Install -minimal <root>` must be run FROM the unpacked tree and pointed at
# the same tree to lay out bin/erl. Skipping that leaves no `bin/erl` at all.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

# ubuntu-24.04 build: its glibc (2.39) is older than trixie's (2.41), so it runs.
URL="https://builds.hex.pm/builds/otp/ubuntu-24.04/OTP-${VERSION}.tar.gz"
echo "erlang: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/otp.tar.gz

rm -rf /tmp/otp-x && mkdir -p /tmp/otp-x
tar -xzf /tmp/otp.tar.gz -C /tmp/otp-x
rm -f /tmp/otp.tar.gz
# The archive's root is OTP-<version>/.
cp -a /tmp/otp-x/OTP-"${VERSION}"/. "$ROOT"/
rm -rf /tmp/otp-x

# Lay the tree out in place: Install must run with cwd inside ERL_ROOT.
( cd "$ROOT" && ./Install -minimal "$ROOT" >/dev/null 2>&1 )

test -x "$ROOT/bin/erl" || { echo "erlang: Install produced no bin/erl" >&2; exit 1; }
"$ROOT/bin/erl" -noshell -eval \
  'io:format("otp ~s~n",[erlang:system_info(otp_release)]),halt().'

mkdir -p "$OUT"
ASSET="$OUT/erlang-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "erlang: wrote $ASSET"
