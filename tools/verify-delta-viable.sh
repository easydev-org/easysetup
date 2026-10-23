#!/bin/bash
# Is a delta scheme actually sound? Three things must hold, and each can fail:
#
#   1. The dependency's closure must be a SUBSET of the dependent's closure.
#      If composer bundles php 8.5.11 but our `php` setup is also 8.5.11, the php
#      paths are identical and can be subtracted. If the versions differ, they
#      are DIFFERENT store paths and subtracting removes nothing - the tarball
#      would then be missing a php that composer expects.
#
#   2. The dependent must not need anything else that the base lacks. A closure
#      that is 90% shared saves 90%; one that is 40% shared saves 40%.
#
#   3. What is left after subtracting must still RUN. A binary whose interpreter
#      was subtracted is broken, and that only shows up when it is executed.
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
export HTTPS_PROXY=http://mihomo.develop.svc.cluster.local:7890
export HTTP_PROXY="$HTTPS_PROXY"
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
cd "$(dirname "$0")/.." || exit 1

W=/data/dverify
rm -rf "$W"; mkdir -p "$W"

paths() {
  "$NIX" build --no-link "$1" >/dev/null 2>&1
  "$NIX" path-info -r "$1" 2>/dev/null | sort
}

report() {
  local label="$1" dep="$2" main="$3"
  echo "===== $label ====="
  paths "$dep"  > "$W/dep"
  paths "$main" > "$W/main"
  local nd nm common
  nd=$(wc -l < "$W/dep")
  nm=$(wc -l < "$W/main")
  comm -12 "$W/dep" "$W/main" > "$W/both"
  common=$(wc -l < "$W/both")
  echo "  $dep : $nd paths"
  echo "  $main: $nm paths"
  echo "  shared : $common"
  echo "  main-only after subtracting the dep: $((nm - common))"
  if [ "$common" -eq "$nd" ]; then
    echo "  VERDICT: dep closure is a SUBSET - delta is sound"
  else
    echo "  VERDICT: NOT a subset - $((nd - common)) dep paths are absent from main"
    echo "           the dep and the main were built against different inputs:"
    comm -23 "$W/dep" "$W/main" | head -5 | sed 's/^/             /'
  fi
  echo
}

report "composer on php85" 'nixpkgs#php85' 'nixpkgs#php85Packages.composer'
report "jq on glibc"       'nixpkgs#glibc' 'nixpkgs#jq'
report "pip on python315"  'nixpkgs#python315' 'nixpkgs#python315Packages.pip'

echo "===== does the difference alone still run? ====="
echo "Staging only the main-only paths for jq and executing its binary."
echo "(If the interpreter was subtracted, this fails - which is the whole point"
echo " of checking rather than assuming.)"
mkdir -p "$W/only/nix/store"
paths 'nixpkgs#jq' > "$W/main" 2>/dev/null
paths 'nixpkgs#glibc' > "$W/dep" 2>/dev/null
comm -23 "$W/main" "$W/dep" > "$W/mainonly"
echo "  jq-only paths: $(wc -l < "$W/mainonly")"
for p in $(cat "$W/mainonly"); do cp -a "$p" "$W/only/nix/store/" 2>/dev/null; done
JQBIN=$(ls -d "$W"/only/nix/store/*-jq-*/bin/jq 2>/dev/null | head -1)
echo "  binary: ${JQBIN:-none}"
if [ -n "$JQBIN" ]; then
  "$JQBIN" --version 2>&1 | head -2 | sed 's/^/    /'
  echo "  exit=$?"
fi
