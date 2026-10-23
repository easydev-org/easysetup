# Generated from matrix-nix.yml by tools/gen-setups.py.
#
# A setup is a nixpkgs attribute plus the name users type. Edit the manifest, not
# this file, unless the setup genuinely needs an override - in which case delete
# the "Generated" line above so regeneration leaves it alone.
#
# crystal needs no override. `nix build .#crystal-1.21.1` correctly produces
# `...-crystal-1.21.1-bin`; only `.outPath` is misleading for this package, and
# compute-deps.py and the audit both read the build's output now instead.
{ pkgs }:
pkgs.crystal
