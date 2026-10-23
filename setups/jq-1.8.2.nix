{ pkgs }:
# `pkgs.jq` alone resolves to the package's DEFAULT output, which for jq is
# `man` - so the closure holds documentation and no binary, and the build fails
# with "has no bin/ or sbin/". Every other setup here is a bare pkgs.<name>
# because their default output is the one with executables; jq is the exception.
pkgs.jq.bin
