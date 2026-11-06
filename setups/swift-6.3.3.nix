{ pkgs }:
# swift, with wrapper scripts that put its runtime libraries on the link path.
#
# THE PROBLEM
# -----------
# nixpkgs installs swift's runtime .so files in `$out/lib`, but the driver has a
# compiled-in search path of `$out/lib/swift/linux`, which holds only
# .swiftmodule files. So `swiftc main.swift -o app` fails:
#
#   ld.bfd: cannot find -lswiftCore
#
# and after adding that one -L it fails again, because libFoundation.so's OWN
# dependencies are in SIBLING store paths:
#
#   ld.bfd: libFoundation.so: undefined reference to `uloc_toLegacyKey'   (ICU)
#
# WHY NOT `overrideAttrs`
# -----------------------
# An override changes swift's derivation, so its store path is no longer the one
# cache.nixos.org has, and producing it means COMPILING swift from source. The
# release pipeline refuses that on purpose:
#
#   if [ "$built" -gt 0 ]; then
#     echo "::error::... is not fully substitutable: N path(s) would be compiled"
#
# That is also why the override this file used to carry never shipped: the
# tarball published on 2026-10-24 predates the override (2026-10-26), so every
# installed swift was the unpatched one.
#
# WHAT THIS DOES INSTEAD
# ----------------------
# `symlinkJoin` reuses the UNCHANGED swift derivation (so the expensive part is
# still a cache download) and replaces the three driver symlinks with wrappers
# that append `-L` and an rpath for every lib directory of the runtime closure.
#
# The flags are baked in rather than left to LIBRARY_PATH, so the published
# tarball also works for a consumer that never sources env.sh (a Dockerfile that
# copies the store path, an editor plugin that shells out to swiftc).
{ pkgs }:
let
  swift = pkgs.swift;

  # Every store path in swift's runtime closure that has a lib/ directory.
  #
  # `pkgs.lib.getLib` collapses a package to ONE output, which is not what a
  # linker needs: ICU's .so files are in ICU's own store path, not swift's. The
  # full closure is the honest list, and it is computed at build time from the
  # same derivation the binary cache supplies.
  runtimePaths = pkgs.lib.closePropagation
    ([ swift ] ++ swift.buildInputs ++ swift.propagatedBuildInputs);
  libDirs = map (p: "${pkgs.lib.getLib p}/lib") runtimePaths;

  # One guarded line per directory. `\$extra` is escaped so the SHELL that writes
  # the wrapper does not expand it; the wrapper does, at run time.
  flagLines = pkgs.lib.concatMapStrings
    (d: ''[ -d "${d}" ] && extra="\$extra -L${d} -Wl,-rpath,${d}"'' + "\n")
    libDirs;
in
pkgs.symlinkJoin {
  name = "swift-${swift.version}";
  paths = [ swift ];
  postBuild = ''
    for prog in swift swiftc swift-driver; do
      target="$out/bin/$prog"
      if [ ! -e "$target" ]; then continue; fi
      # -f follows the symlink the join created, so this works whatever layout
      # nixpkgs uses; the wrapper then execs that absolute path.
      real="$(readlink -f "$target")"
      rm -f "$target"
      cat > "$target" <<EASYDEV_WRAPPER_EOF
    #!${pkgs.runtimeShell}
    # Put swift's runtime libraries on the link path AND the run path, so a
    # program built here also FINDS them when it runs.
    # nixpkgs keeps them in \$out/lib but the driver searches
    # \$out/lib/swift/linux (only .swiftmodule files there), and libFoundation.so
    # needs ICU from a SIBLING store path. See setups/swift-6.3.3.nix.
    extra=""
    ${flagLines}
    exec "$real" \$extra "\$@"
    EASYDEV_WRAPPER_EOF
      chmod +x "$target"
    done
  '';
}
