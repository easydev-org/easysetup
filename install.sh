#!/bin/bash
# install.sh — install one or more easysetup toolchains into /opt/setup.
#
#   ./install.sh node-22.23.4 python-3.12.15
#   ./install.sh --list
#
# INSTALL CONTRACT, and every setup obeys it:
#   1. apt-get the packages listed in the entry's apt_deps (shared libraries),
#   2. download the ONE prebuilt tarball the entry names,
#   3. verify its sha256,
#   4. unpack it at /.
# Nothing is compiled here and nothing else is downloaded. The toolchain was
# built and pinned in advance; this script only installs it.
#
# Each entry installs into /opt/setup/<tool>-<version>, so two versions of a
# tool coexist. /opt/setup/env.sh is rewritten to put exactly what this run
# installed on PATH.
set -euo pipefail

REPO="${EASYSETUP_REPO:-easydev-org/easysetup}"
RAW="https://raw.githubusercontent.com/${REPO}/main"
BASE="https://github.com/${REPO}/releases/download"

command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "install.sh: python3 is required (PyYAML)" >&2; exit 1; }

# matrixlib.py + matrix.yml are downloaded together and parsed by the SAME code
# the release pipeline uses. An awk re-implementation here is what let the two
# drift apart before.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 3 -o "$WORK/matrix.yml" "$RAW/matrix.yml" || {
  echo "install.sh: cannot read the manifest" >&2; exit 1; }
curl -fsSL --retry 3 -o "$WORK/matrixlib.py" "$RAW/matrixlib.py" || {
  echo "install.sh: cannot read matrixlib.py" >&2; exit 1; }

mlib() { ( cd "$WORK" && python3 matrixlib.py "$@" ); }

if [ "$#" -eq 0 ]; then
  echo "install.sh: name at least one setup; 'install.sh --list' shows them" >&2
  exit 2
fi

if [ "$1" = "--list" ]; then
  mlib list
  exit 0
fi

mkdir -p /opt/setup
installed=""

# Flatten every requested name into an install order, dependencies first, with
# each setup appearing once. `install.sh elixir-1` therefore installs erlang
# before elixir, and asking for both does not install erlang twice.
ALL=""
for name in "$@"; do
  chain=$(mlib resolve "$name") || {
    echo "install.sh: cannot resolve '$name'" >&2
    echo "            available: $(mlib list | tr '\n' ' ')" >&2
    exit 2
  }
  for id in $chain; do
    case " $ALL " in
      *" $id "*) ;;
      *) ALL="$ALL $id" ;;
    esac
  done
done

for id in $ALL; do
  tool=$(mlib get "$id" tool)
  version=$(mlib get "$id" version)
  artifact=$(mlib get "$id" artifact)
  sha=$(mlib get "$id" sha256)

  echo "==> $id ($tool $version)"

  # 0) Idempotence. `install.sh` is called once per `uses:` step, and people
  #    legitimately ask for the same tool twice (or for two setup names that
  #    share a dependency). Re-downloading a 200 MB tarball to unpack it over
  #    itself is slow and pointless, so skip anything already present and
  #    already matching the pin we recorded at install time.
  marker="/opt/setup/$id/.easysetup"
  if [ -d "/opt/setup/$id" ] && [ -f "$marker" ]; then
    prev=$(sed -n 's/^sha256=//p' "$marker" | head -1)
    if [ "$prev" = "$sha" ] && [ -n "$sha" ]; then
      echo "    already installed at /opt/setup/$id (sha256 matches), skipping"
      installed="$installed $id"
      continue
    fi
  fi

  # 1) base packages. Only shared libraries: the toolchain itself always comes
  #    from the release, so its version is exactly the pin.
  deps=$(mlib apt "$id")
  if [ -n "$deps" ]; then
    echo "    apt: $deps"
    if command -v apt-get >/dev/null; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      # shellcheck disable=SC2086
      apt-get install -y -qq --no-install-recommends $deps
    else
      echo "install.sh: this setup needs debian (apt-get not found)" >&2; exit 1
    fi
  fi

  # 2) the prebuilt tarball.
  url="$BASE/$id/$artifact"
  echo "    fetch: $url"
  curl -fsSL --http1.1 --retry 3 --retry-delay 2 -o "$WORK/asset" "$url" || {
    echo "install.sh: download failed for $artifact" >&2; exit 1; }

  # 3) checksum. An empty pin means the release was not cut for this entry;
  #    refuse rather than unpack whatever arrived.
  if [ -n "$sha" ]; then
    echo "$sha  $WORK/asset" | sha256sum -c - >/dev/null || {
      echo "install.sh: sha256 mismatch for $artifact" >&2; exit 1; }
  else
    echo "install.sh: no pinned sha256 for $id; refusing to unpack" >&2; exit 1
  fi

  # 4) unpack at / — the archive already carries opt/setup/<id>/.
  tar -xJf "$WORK/asset" -C /
  rm -f "$WORK/asset"
  # A setup comes in one of two layouts:
  #
  #   normal:  opt/setup/<id>/...          (everything the other build scripts make)
  #   nixpkg:  nix/store/<hash>-<name>/... plus nix/setup-root-<dir> written by
  #            build-nixpkg.sh. The closure must stay at /nix/store because every
  #            binary in it has absolute /nix/store paths baked in; moving it
  #            breaks PT_INTERP. So this layout is accepted as-is, and the
  #            metadata file tells gen-env.sh where the binaries are. It is per
  #            setup so several nix setups can coexist.
  if [ -d "/opt/setup/$id" ]; then
    :
  elif [ -f "/nix/setup-root-$id" ]; then
    echo "    nix closure unpacked at /nix/store (see /nix/setup-root-$id)"
    # Keep a discoverable link so /opt/setup/<id> still means something, and so
    # a second run recognises this setup as installed.
    mkdir -p /opt/setup
    rm -f "/opt/setup/$id"
    ln -s "$(cut -d'|' -f1 "/nix/setup-root-$id")" "/opt/setup/$id"
  else
    echo "install.sh: $artifact produced neither /opt/setup/$id nor /nix/setup-root-$id" >&2
    exit 1
  fi
  # 4b) A few tools cannot live under /opt/setup at all and must be materialised
  #     at their compiled-in root. Nix is that case: every store path and profile
  #     link inside the tree points at /nix, so it only works there. The tarball
  #     is staged under /opt/setup/<id> and then copied into place.
  case "$id" in
    nix-*)
      echo "    materialising /nix from the setup tree (nix hard-codes that path)"
      mkdir -p /nix
      cp -a "/opt/setup/$id/." /nix/
      ;;
  esac
  # Record what was unpacked, so a second run can tell "already done" from
  # "a different pin is wanted".
  printf 'id=%s\nsha256=%s\nartifact=%s\n' "$id" "$sha" "$artifact" > "$marker"
  installed="$installed $id"
done

# 5) Regenerate /opt/setup/env.sh from EVERYTHING on disk, not just this run.
#
#    install.sh is invoked once per `uses:` step, so generating env.sh from
#    "$installed" made the last call silently erase what the previous ones had
#    installed. Scanning the directory fixes that, and gen-env.sh also feeds
#    $GITHUB_PATH so a following `run:` step sees the tools at all.
curl -fsSL --retry 3 -o "$WORK/gen-env.sh" "$RAW/tools/gen-env.sh" || {
  echo "install.sh: cannot fetch gen-env.sh" >&2; exit 1; }
bash "$WORK/gen-env.sh" /opt/setup/env.sh

echo "==> installed:$installed"
echo "    now run:  . /opt/setup/env.sh"

