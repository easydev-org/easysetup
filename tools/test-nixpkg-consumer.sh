#!/bin/bash
# Simulate the CONSUMER side of a nix-built setup: no nix, just tar.
#
# This is the claim that matters. If it holds, "build with nix, ship a tarball"
# is sound, because the user needs nothing but curl and tar.
#
# Method: unpack the asset into an otherwise EMPTY root and chroot into it. Any
# /nix the host has is invisible from inside, so a pass cannot be an accident.
#
# Usage: test-nixpkg-consumer.sh <asset.tar.xz> [binary] [args...]
set -uo pipefail

TARBALL="$1"; shift || true
BIN="${1:-hello}"; shift || true

W=/data/nixpkg-consumer
rm -rf "$W"
mkdir -p "$W/root"

echo "== unpacking into an empty root =="
tar -xJf "$TARBALL" -C "$W/root"
echo "   top level: $(ls "$W/root" | tr '\n' ' ')"

echo
echo "== metadata the installer reads =="
cat "$W/root/nix/setup-root" 2>/dev/null || echo "   (missing setup-root)"

ROOTPATH=$(cut -d'|' -f1 "$W/root/nix/setup-root" 2>/dev/null)
DIRS=$(cut -d'|' -f2 "$W/root/nix/setup-root" 2>/dev/null)

echo
echo "== host nix presence (must not matter) =="
if [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  echo "   host HAS nix; the chroot will not see it - that is the point"
else
  echo "   host has NO nix"
fi

echo
echo "== run inside a chroot containing ONLY the asset =="
firstdir=$(echo "$DIRS" | awk '{print $1}')
chroot "$W/root" "$ROOTPATH/$firstdir/$BIN" "$@" 2>&1 | head -5
echo "   exit=$?"

echo
echo "== the chroot has no /usr, no shell, no nix - only the closure =="
ls "$W/root"
