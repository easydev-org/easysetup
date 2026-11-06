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
# and after fixing that, libFoundation.so's OWN dependencies are in SIBLING store
# paths:
#
#   ld.bfd: libFoundation.so: undefined reference to `uloc_toLegacyKey'   (ICU)
#
# WHY NOT `overrideAttrs`
# -----------------------
# An override changes swift's derivation, so its store path is no longer the one
# cache.nixos.org has, and producing it means COMPILING swift from source. The
# release pipeline refuses that on purpose (a compiled toolchain can take hours
# and is indistinguishable from a cached one in the tarball).
#
# WHAT THIS DOES INSTEAD
# ----------------------
# A tiny `runCommand` derivation produces the env file and the wrapper scripts;
# `symlinkJoin` then overlays them onto the UNCHANGED swift. Every heavy input is
# still a cache download.
#
# WHERE THE DIRECTORY LIST COMES FROM
# -----------------------------------
# `pkgs.closureInfo` walks the references nix RECORDED for swift's output. That is
# the only honest source: `buildInputs` is a build-time list and does not contain
# the runtime dependencies, and hardcoding `pkgs.icu` is wrong as well -- the ICU
# swift actually links against is `swift-foundation-icu` (76142.4.7), not
# nixpkgs' icu4c, and naming the wrong one leaves the undefined symbols in place.
#
# WHY THE FLAGS ARE IN AN ENV FILE AND NOT IN argv
# -----------------------------------------------
# `swiftc` forwards its argv to `swift-driver`, and the driver rejects compiler
# flags:
#
#   error: invalid driver name: swift-driver
#
# LIBRARY_PATH is read by the LINKER (the component that needs the search path)
# and ignored by the driver, which is exactly the split we want.
#
# glibc is NEVER added to LD_LIBRARY_PATH: a nix glibc on the loader path breaks
# unrelated processes on the host.
let
  inherit (pkgs) lib;

  # Every store path in swift's runtime closure, computed by nix itself.
  closure = pkgs.closureInfo { rootPaths = [ pkgs.swift ]; };

  # Exports the link and run paths. Written at BUILD time because the closure can
  # only be enumerated then.
  #
  # glibc is filtered out: on LD_LIBRARY_PATH it breaks unrelated host processes,
  # and the linker already reaches it through the toolchain. Every other lib dir in
  # the closure is listed, because a missing one is exactly the bug being fixed and
  # an extra one holds no symbol the linker wants.
  linkEnv = pkgs.runCommand "swift-link-env" { } ''
    libdirs=""
    while IFS= read -r p; do
      case "$p" in
        *glibc*) continue ;;
      esac
      if [ -d "$p/lib" ]; then
        libdirs="$libdirs $p/lib"
      fi
    done < ${closure}/store-paths

    mkdir -p "$out"
    {
      echo 'easydev_rpath=""'
      for d in $libdirs; do
        printf 'export LIBRARY_PATH="%s:$LIBRARY_PATH"\n' "$d"
        printf 'export LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\n' "$d"
        easydev_rpath="$easydev_rpath -Wl,-rpath,$d"
      done
      printf 'export NIX_LDFLAGS="%s $NIX_LDFLAGS"\n' "$easydev_rpath"
      echo 'unset easydev_rpath'
    } > "$out/link-env.sh"

    echo "swift-link-env: $(grep -c LIBRARY_PATH "$out/link-env.sh") lib dir(s)"
  '';

  # `swift` and `swiftc` are front ends that exec the driver; the driver itself is
  # left untouched (it rejects compiler flags, and the LINKER is what reads
  # LIBRARY_PATH).
  #
  # writeScript, not a heredoc inside an indented nix string: those keep their
  # leading spaces, and a shebang that is not at column 0 is not a shebang.
  mkWrapper = prog: pkgs.writeScript "swift-${prog}-wrapper" ''
    #!${pkgs.runtimeShell}
    # Put swift's runtime libraries on the link path (LIBRARY_PATH) and the run
    # path (LD_LIBRARY_PATH). See setups/swift-6.3.3.nix.
    . ${linkEnv}/link-env.sh
    exec ${pkgs.swift}/bin/${prog} "$@"
  '';

  wrappers = pkgs.runCommand "swift-wrappers" { } (
    lib.concatMapStrings (prog: ''
      mkdir -p "$out/bin"
      cp ${mkWrapper prog} "$out/bin/${prog}"
      chmod +x "$out/bin/${prog}"
    '') [ "swift" "swiftc" ]
  );
in
pkgs.symlinkJoin {
  name = "swift-${pkgs.swift.version}";
  # `wrappers` is FIRST: with ignoreCollisions the first path to provide a name
  # wins, so listing it last would leave swift's own bin/swift in place (an earlier
  # revision did, and the probe found an ELF binary where it expected the script).
  paths = [ wrappers pkgs.swift ];
  ignoreCollisions = true;
}
