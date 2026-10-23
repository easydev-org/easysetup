#!/bin/bash
# Why does `.#<name>` fail when `.#versions."<name>"` succeeds?
#
# Both read the same ./setups directory, so a difference between them points at
# how nix copies the flake source: only git-TRACKED files are put in the store.
# This prints the three things needed to tell those apart.
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)

echo "== cwd =="
pwd

echo
echo "== setup files on disk =="
ls setups/*.nix | wc -l

echo
echo "== git state =="
git rev-parse --short HEAD
git status --short | head -5
echo "tracked in setups/: $(git ls-files setups/ | wc -l)"

echo
echo "== what nix sees for both attribute trees =="
for kind in versions packages; do
  printf '%-10s ' "$kind"
  if [ "$kind" = versions ]; then
    "$NIX" eval --impure --json '.#versions' 2>/dev/null \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); ks=sorted(d); print(len(ks), ks[:3])' || echo "FAILED"
  else
    "$NIX" eval --impure --json '.#packages.x86_64-linux' 2>/dev/null \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); ks=sorted(d); print(len(ks), ks[:3])' || echo "FAILED"
  fi
done

echo
echo "== can each be addressed by name? =="
"$NIX" eval --raw '.#versions."jq-1.8.2"' 2>&1 | head -3
"$NIX" build --no-link --dry-run '.#jq-1.8.2' 2>&1 | head -3

echo
echo "== is the failing name perhaps being parsed with the dots as a path? =="
echo "-- quoted form (what should work):"
"$NIX" build --no-link --dry-run '.#"jq-1.8.2"' 2>&1 | head -3
echo "-- unquoted form (dots read as attribute separators):"
"$NIX" build --no-link --dry-run '.#jq-1.8.2' 2>&1 | head -3

echo
echo "== does a DOT-FREE name work? =="
# cmake-4.4.4 has dots too; use a name with no dot at all if one exists.
DOTFREE=$(ls setups/*.nix | xargs -n1 basename | sed 's/\.nix$//' | grep -v '\.' | head -1)
if [ -n "$DOTFREE" ]; then
  echo "trying $DOTFREE"
  "$NIX" build --no-link --dry-run ".#$DOTFREE" 2>&1 | head -3
else
  echo "every setup name contains a dot"
fi
