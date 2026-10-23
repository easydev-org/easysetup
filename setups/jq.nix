{ pkgs }:
# `pkgs.jq` alone resolves to the package's default output, which for jq is
# `man` - the closure then holds documentation and no binary at all. Naming the
# output explicitly is the fix.
#
# This is the one place a setup is not just `pkgs.<name>`, and it is worth
# knowing why: nix allows a package to expose several outputs, and the default
# is not guaranteed to be the one with the executables.
pkgs.jq.bin
