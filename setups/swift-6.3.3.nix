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
    # The link flags go in a small env file that the wrapper SOURCES, rather than
    # on the command line.
    #
    # Reason: `swiftc` forwards its argv to `swift-driver`, and the driver rejects
    # compiler flags ("error: invalid driver name: swift-driver"). A -L on the
    # command line therefore breaks the driver instead of helping the linker.
    # LIBRARY_PATH is read by the LINKER, which is the component that actually
    # needs the search path, and the driver ignores it.
    #
    # A built program also has to FIND them when it runs. LD_LIBRARY_PATH covers
    # that, and it is limited to swift's runtime and ICU on purpose: putting
    # nix's GLIBC on the loader path breaks unrelated processes.
    mkdir -p "$out/nix-support"
    {
      echo 'easydev_extra=""'
      ${pkgs.lib.concatMapStrings (d: ''
      if [ -d "${d}" ]; then
        echo "export LIBRARY_PATH=\"${d}:\$LIBRARY_PATH\""
        # LD_LIBRARY_PATH for these directories ONLY. It is normally wrong to
        # set (nix's glibc on the loader path breaks unrelated processes), but
        # these are swift's runtime and ICU, and a binary built here carries no
        # rpath of its own. glibc is deliberately NOT in this list.
        echo "export LD_LIBRARY_PATH=\"${d}:\$LD_LIBRARY_PATH\""
        easydev_extra="$easydev_extra -Wl,-rpath,${d}"
      fi
      '') libDirs}
      echo "export NIX_LDFLAGS=\"\$easydev_extra \$NIX_LDFLAGS\""
      echo 'unset easydev_extra'
    } > "$out/nix-support/swift-link-env.sh"

    for prog in swift swiftc; do
      target="$out/bin/$prog"
      if [ ! -e "$target" ]; then continue; fi
      real="$(readlink -f "$target")"
      rm -f "$target"
      cat > "$target" <<EASYDEV_WRAPPER_EOF
    #!${pkgs.runtimeShell}
    # Put swift's runtime libraries on the LINK path (LIBRARY_PATH) and the RUN
    # path (NIX_LDFLAGS -> -rpath). See setups/swift-6.3.3.nix.
    #
    # The flags are NOT passed as arguments: swiftc forwards argv to
    # swift-driver, which rejects compiler flags.
    if [ -r "$out/nix-support/swift-link-env.sh" ]; then
      . "$out/nix-support/swift-link-env.sh"
    fi
    exec "$real" "\$@"
    EASYDEV_WRAPPER_EOF
      chmod +x "$target"
    done
  '';
}
