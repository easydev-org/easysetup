#!/bin/bash
# Where does composer live in nixpkgs, and does it work on its own?
#
# Two shapes are possible:
#   pkgs.php.packages.composer   the per-PHP-version package set (php85Packages)
#   pkgs.phpPackages.composer    the default PHP's package set
#   pkgs.composer                a standalone one, if it exists
#
# Which one is right matters: composer is a PHP program, so it must run on the
# PHP we ship. If it comes from a different PHP build, its shebang points at a
# php the user does not have.
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
cd "$(dirname "$0")/.." || exit 1

probe() {
  local attr="$1" v
  v=$("$NIX" eval --raw "nixpkgs#\"$attr\".version" 2>/dev/null) || v=""
  if [ -n "$v" ]; then printf '  %-40s %s\n' "$attr" "$v"
  else printf '  %-40s %s\n' "$attr" "-"; fi
}

echo "== composer candidates =="
probe composer
probe php.packages.composer
probe php85.packages.composer
probe php84.packages.composer
probe php83.packages.composer
probe php82.packages.composer
probe phpPackages.composer
probe php85Packages.composer

echo
echo "== other per-PHP tools worth having =="
probe php.packages.php-cs-fixer
probe php.packages.psalm
probe php.packages.phpstan
probe php.packages.phpunit
probe php.packages.box
probe php.packages.phing

echo
echo "== jenkins plugin tool (what we had as jenkins-plugin-cli) =="
probe jenkins
probe jenkins-plugin-manager
probe jenkinsPlugins
