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
# still a cache download) and only adds three tiny wrapper scripts. The wrappers
# append `-L`/`-rpath` for every lib directory of swift's runtime closure.
#
# The flags are baked in rather than left to LIBRARY_PATH, so the published
# tarball also works for a consumer that never sources env.sh (a Dockerfile that
# copies the store path, an editor plugin that shells out to swiftc).
{ pkgs }:
let
  swift = pkgs.swift;

  # Every store path in swift's runtime closure that has a lib/ directory.
  #
  # `pkgs.lib.getLib` would collapse to one output per package, which is not what
  # a linker needs: ICU's .so files are in ICU's own store path, not in swift's.
  # The full closure is the honest list, and it is computed at build time from
  # the same derivation the cache supplies.
  runtimePaths = pkgs.lib.closePropagation ([ swift ] ++ swift.buildInputs ++ swift.propagatedBuildInputs);
  libDirs = map (p: "${pkgs.lib.getLib p}/lib") runtimePaths;
in
pkgs.symlinkJoin {
  name = "swift-${swift.version}";
  paths = [ swift ];
  # One wrapper per driver entry point: `swift build` calls swiftc, and tools
  # call swift, so all three need the flags.
  postBuild = ''
    for prog in swift swiftc swift-driver; do
      target="$out/bin/$prog"
      if [ ! -e "$target" ]; then continue; fi
      real="$(readlink -f "$target")"
      rm -f "$target"
      {
        echo '#!'"${pkgs.runtimeShell}"
        echo '# Put swift'"'"'s runtime libraries on the link path.'
        echo '#'
        echo '# nixpkgs installs them in $out/lib but the driver searches'
        echo '# $out/lib/swift/linux, which has only .swiftmodule files. libFoundation.so'
        echo '# in turn needs ICU, in a SIBLING store path. See setups/swift-6.3.3.nix.'
        echo 'extra=""'
        echo 'for d in '"$(printf '%s ' "${libDirs[@]}")"'; do'
        echo '  [ -d "$d" ] || continue'
        echo '  extra="$extra -L$d -Wl,-rpath,$d"'
        echo 'done'
        echo 'exec '"$real"' $extra "$@"'
      } > "$target"
      chmod +x "$target"
    done
  '';
}
