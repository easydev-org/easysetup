#!/bin/bash
# build-perl.sh <dir> <version> <outdir>
# skaji/relocatable-perl: a perl that runs from any prefix, with cpanm
# bundled - exactly the client the `cpan` protocol needs.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
STAGE=$(mktemp -d); ROOT="$STAGE/opt/setup/$DIR"; mkdir -p "$ROOT"

URL="https://github.com/skaji/relocatable-perl/releases/download/${VERSION}/perl-linux-amd64.tar.xz"
echo "perl: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/perl.tar.xz
rm -rf /tmp/perl-x && mkdir -p /tmp/perl-x
tar -xJf /tmp/perl.tar.xz -C /tmp/perl-x
# The archive's root is perl-linux-amd64/.
cp -a /tmp/perl-x/perl-linux-amd64/. "$ROOT"/
rm -rf /tmp/perl.tar.xz /tmp/perl-x

"$ROOT/bin/perl" -v 2>&1 | sed -n 2p
test -x "$ROOT/bin/cpanm" || { echo "perl: cpanm missing (needed for the cpan protocol)" >&2; exit 1; }
"$ROOT/bin/perl" "$ROOT/bin/cpanm" --version

mkdir -p "$OUT"
ASSET="$OUT/perl-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "perl: wrote $ASSET"
