# Generated from matrix-nix.yml by tools/gen-setups.py.
#
# A setup is a nixpkgs attribute plus the name users type. Edit the manifest, not
# this file, unless the setup genuinely needs an override - in which case delete
# the "Generated" line above so regeneration leaves it alone.
#
# pecl is not its own attribute: PHP's --with-pear build step installs php, pear
# and pecl into one $out/bin, so this entry names php85 and the tarball is the
# same content php's is. That is why the version is PHP's 8.5.11.
{ pkgs }:
pkgs.php85
