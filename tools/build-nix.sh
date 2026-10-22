#!/bin/bash
# build-nix.sh <dir> <version> <outdir>
#
# Nix, installed in SINGLE-USER mode and then re-packed.
#
# Single-user is the whole point here: the multi-user install needs a daemon,
# a `nixbld` group and systemd, none of which exist in a CI container. With
# --no-daemon everything lives under /nix and no service is required.
#
# Two things the official tarball makes awkward, both handled below:
#
#   * `install` hard-codes dest="/nix" and calls `sudo mkdir`. In a container we
#     are already root, so /nix is created here and sudo is stubbed out.
#   * the installer insists the `nixbld` group exists even for a single-user
#     install (it warns, then fails when registering the profile). The group
#     and its build users are created first.
#
# The tarball ships its own /nix/store with every dependency, so nothing is
# fetched at install time - which is exactly the contract the rest of easysetup
# follows.
set -euo pipefail

. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-relocate.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://releases.nixos.org/nix/nix-${VERSION}/nix-${VERSION}-x86_64-linux.tar.xz"
echo "nix: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/nix.tar.xz

rm -rf /tmp/nix-x && mkdir -p /tmp/nix-x
tar -xJf /tmp/nix.tar.xz -C /tmp/nix-x
rm -f /tmp/nix.tar.xz
SRC=$(find /tmp/nix-x -maxdepth 1 -mindepth 1 -type d | head -1)
[ -n "$SRC" ] || { echo "nix: unexpected tarball layout" >&2; exit 1; }

export HOME="${HOME:-/root}"
export USER="${USER:-root}"

# The installer shells out to `sudo mkdir` when /nix is missing, but it also
# checks NIX_BECOME. Nix supports overriding it, so point it at nothing and
# create the directory ourselves - we are root in the build container.
mkdir -m 0755 -p /nix
export NIX_BECOME=""

# A single-user install still registers the profile as the nixbld group.
if ! getent group nixbld >/dev/null 2>&1; then
  groupadd -r nixbld
  i=1
  while [ "$i" -le 10 ]; do
    id -u "nixbld$i" >/dev/null 2>&1 || \
      useradd -r -g nixbld -G nixbld -d /var/empty -s /sbin/nologin "nixbld$i" 2>/dev/null || true
    i=$((i + 1))
  done
fi

echo "nix: installing single-user into /nix"
sh "$SRC/install" --no-daemon --yes --no-channel-add 2>&1 | tail -6

test -x /nix/var/nix/profiles/default/bin/nix || {
  echo "nix: install produced no binary" >&2; exit 1; }

# Enable the modern CLI for the consumer. Without this every `nix build` dies
# with "experimental Nix feature 'nix-command' is disabled".
mkdir -p /root/.config/nix
if [ ! -f /root/.config/nix/nix.conf ]; then
  printf 'experimental-features = nix-command flakes\n' > /root/.config/nix/nix.conf
fi

/nix/var/nix/profiles/default/bin/nix --version

# Repack /nix as the setup tree: the whole store IS the installation.
cp -a /nix/. "$ROOT"/
echo "nix: tree is $(du -sh "$ROOT" | cut -f1)"

mkdir -p "$OUT"
ASSET="$OUT/nix-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "nix: wrote $ASSET ($(du -h "$ASSET" | cut -f1))"
