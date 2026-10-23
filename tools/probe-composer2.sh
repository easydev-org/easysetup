#!/bin/bash
# The `.version` probe returned "-" for everything, including paths that should
# exist. That usually means the attribute exists but has no `version` field at
# the level we asked, so this checks existence and content separately:
#
#   nix eval .#<attr>            does it evaluate at all?
#   builtins.attrNames on the PHP package set   what is actually in there?
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
cd "$(dirname "$0")/.." || exit 1

echo "== does the composer attribute evaluate? (name + outPath, no version) =="
for a in composer php.packages.composer php85.packages.composer; do
  printf '%-34s ' "$a"
  out=$("$NIX" eval --raw "nixpkgs#\"$a\".name" 2>&1 | head -2 | tr '\n' ' ')
  echo "$out" | cut -c1-100
done

echo
echo "== what is actually in the PHP 8.5 package set? =="
"$NIX" eval --json --apply 'x: builtins.attrNames x' "nixpkgs#php85.packages" 2>&1 \
  | head -c 2000
echo
