{ pkgs }:
# `pkgs.jq` alone resolves to the package's DEFAULT output, which for jq is
# `man` - the closure then holds documentation and no binary, and the build fails
# with "has no bin/ or sbin/". Every other setup here is a bare pkgs.<name>
# because their default output has the executables; jq is the exception.
#
# This file carries no "Generated" marker, so tools/gen-setups.py leaves it alone
# instead of overwriting the override.
pkgs.jq.bin
