#!/bin/bash
# Verify php85Packages.composer: does it exist, what does it depend on, and does
# its binary run on its own?
#
# The last point is the one that matters. composer is a PHP program, so its
# launcher has a `#!/nix/store/...-php-8.5.x/bin/php` shebang. Whether that works
# without a separately installed php depends on whether the closure ships that
# interpreter - which `nix path-info -r` answers.
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
export HTTPS_PROXY=http://mihomo.develop.svc.cluster.local:7890
export HTTP_PROXY=$HTTPS_PROXY
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
cd "$(dirname "$0")/.." || exit 1

echo "== does php85Packages.composer evaluate? =="
"$NIX" eval --raw 'nixpkgs#php85Packages.composer.name' 2>&1 | head -3

echo
echo "== what would it build to? =="
"$NIX" build --no-link --print-out-paths 'nixpkgs#php85Packages.composer' 2>&1 | tail -3
OUT=$("$NIX" build --no-link --print-out-paths 'nixpkgs#php85Packages.composer' 2>/dev/null | tail -1)
echo "out: $OUT"

echo
echo "== is a PHP interpreter inside its own closure? =="
"$NIX" path-info -r "$OUT" 2>/dev/null | grep -c 'php' || true
"$NIX" path-info -r "$OUT" 2>/dev/null | grep 'php-8' | head -3

echo
echo "== the binary itself =="
ls -l "$OUT/bin" 2>/dev/null | head -5
head -1 "$OUT/bin/composer" 2>/dev/null
