# One setup, one expression.
#
# The whole point of this refactor: a setup is a nixpkgs attribute, and the only
# thing easysetup adds is "which attribute, under which name". Keeping it as a
# .nix file rather than a line in a YAML list means the entry can grow into an
# override when one is genuinely needed, without changing the pipeline.
#
# The function shape ({ pkgs }: ...) is what build-nixpkg.sh calls:
#
#     nix build --impure --expr \
#       'let pkgs = import <nixpkgs> {}; in (import ./setups/swift.nix) { inherit pkgs; }'
#
# which keeps the nixpkgs revision under our control (one pin for every setup)
# instead of letting each file pick its own.
{ pkgs }:
pkgs.swift
