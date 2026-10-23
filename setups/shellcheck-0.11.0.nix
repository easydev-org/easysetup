{ pkgs }:
# `pkgs.shellcheck` resolves to the package's DEFAULT output, which here is
# `man` - documentation, no binary. Same trap as jq. Naming the output is the fix.
pkgs.shellcheck.bin
