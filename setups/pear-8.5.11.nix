# Generated from matrix-nix.yml by tools/gen-setups.py.
#
# A setup is a nixpkgs attribute plus the name users type. Edit the manifest, not
# this file, unless the setup genuinely needs an override - in which case delete
# the "Generated" line above so regeneration leaves it alone.
#
# Same story as pecl: pear ships inside php85 ($out/bin/pear), so this entry names
# php85 and carries php's version.
{ pkgs }:
pkgs.php85
