#!/bin/bash
# Does python ship pip? Does php ship composer? And when they don't, how much
# does installing them separately cost?
#
# The concern this tests: if `pip` is a SEPARATE setup whose closure contains its
# own python, then `tools: "python pip"` downloads python twice. That is not a
# rounding error - python is ~89 MB compressed.
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
export HTTPS_PROXY=http://mihomo.develop.svc.cluster.local:7890
export HTTP_PROXY="$HTTPS_PROXY"
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
cd "$(dirname "$0")/.." || exit 1

show() {
  local label="$1"; shift
  printf '\n== %s ==\n' "$label"
  for a in "$@"; do
    printf '  %-44s ' "$a"
    out=$("$NIX" eval --raw "nixpkgs#\"$a\".name" 2>/dev/null | head -1)
    [ -n "$out" ] && echo "$out" || echo "-"
  done
}

# What does python315 expose?
echo "== bins inside nixpkgs#python315 =="
OUT=$("$NIX" build --no-link --print-out-paths 'nixpkgs#python315' 2>/dev/null | tail -1)
ls "$OUT/bin" 2>/dev/null | tr -d '\000' | grep -E 'pip|python' | head -6

echo
echo "== does python315's OWN closure already include pip? =="
"$NIX" path-info -r "$OUT" 2>/dev/null | grep -c 'pip' || echo 0

show "pip candidates" python315Packages.pip python3Packages.pip pip python315.pkgs.pip
show "php/composer" php85Packages.composer php85

echo
echo "== php85's own bin: is composer there? =="
PH=$("$NIX" build --no-link --print-out-paths 'nixpkgs#php85' 2>/dev/null | tail -1)
ls "$PH/bin" 2>/dev/null | tr -d '\000' | head -10
