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
# honours NIX_BECOME. We are root in the build container, so create the
# directory ourselves and point NIX_BECOME at nothing.
#
# The nixbld group and its users are required even for --no-daemon: the
# installer registers the profile through nix-env, which reads
# build-users-group from the packaged nix.conf.
if ! getent group nixbld >/dev/null 2>&1; then
  groupadd -r nixbld
fi
i=1
while [ "$i" -le 10 ]; do
  id -u "nixbld$i" >/dev/null 2>&1 || \
    useradd -r -g nixbld -G nixbld -d /var/empty -s /sbin/nologin "nixbld$i" 2>/dev/null || true
  i=$((i + 1))
done

# Start from a clean /nix owned by root with mode 0755, and let the installer
# create and own the store itself - that is what made the manual trial work.
# Pre-creating /nix/store with nixbld ownership instead breaks the
# user-environment build with EPERM.
rm -rf /nix
mkdir -m 0755 /nix
export NIX_BECOME=""

# In a single-user install there is no daemon and no setuid wrapper, so nix must
# build as root: it has no way to switch to a nixbld user. An empty
# build-users-group tells it to build in-process as root. Without this, nix-env
# tries to create the user-environment as a build user and dies with EPERM,
# which the installer reports as "unable to install Nix into your default
# profile".
export NIX_CONFIG="build-users-group ="

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
#
# Nix hard-codes /nix everywhere - profiles link to /nix/var/..., and the store
# paths inside every binary point at /nix/store. So the tree is NOT relocatable
# to /opt/setup/<id>/ and must be installed at /nix. Two consequences:
#
#   * the payload keeps its own layout (store/, var/) and the consumer's env.sh
#     puts /nix/var/nix/profiles/default/bin on PATH, not <tree>/bin;
#   * this tarball must be unpacked at /, which install.sh already does, and it
#     lands under /opt/setup/<id> only as a staging name - see the note in
#     matrix.yml and the nix branch in install.sh.
cp -a /nix/. "$ROOT"/
echo "nix: tree is $(du -sh "$ROOT" | cut -f1)"

# A bin/ shim so the generic "add <tree>/bin to PATH" rule finds something, and
# so `nix` answers even before /nix is populated by install.sh.
mkdir -p "$ROOT/bin"
for b in nix nix-build nix-channel nix-collect-garbage nix-copy-closure nix-env \
         nix-hash nix-instantiate nix-prefetch-url nix-shell nix-store; do
  real="/nix/var/nix/profiles/default/bin/$b"
  [ -x "$real" ] || continue
  printf '#!/bin/sh\nexec /nix/var/nix/profiles/default/bin/%s "$@"\n' "$b" \
    > "$ROOT/bin/$b"
  chmod +x "$ROOT/bin/$b"
done
echo "nix: bin shims: $(ls "$ROOT/bin" | wc -l)"

mkdir -p "$OUT"
ASSET="$OUT/nix-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "nix: wrote $ASSET ($(du -h "$ASSET" | cut -f1))"
