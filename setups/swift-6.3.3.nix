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
# A tiny `runCommand` derivation produces the wrapper scripts and the env file
# they source; `symlinkJoin` then overlays that onto the UNCHANGED swift. Every
# heavy input is still a cache download.
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

  # The library directories the linker must see.
  #
  # swift's output holds libswiftCore and libFoundation, but libFoundation's own
  # dependencies (ICU) are separate store paths. `buildInputs` is a BUILD-time
  # list, so it does not contain them. ICU is named explicitly: it is the one
  # runtime dependency the published swift is known to need, and it is already
  # part of the closure that gets downloaded anyway.
  #
  # An extra -L to a directory that holds no needed symbol is harmless; a missing
  # one is the exact failure being fixed.
  extraLibs = [ pkgs.icu ];
  libDirs = map (p: "${lib.getLib p}/lib") ([ pkgs.swift ] ++ extraLibs);

  # The env file the wrappers source: one export per directory, plus an rpath set
  # for any program that is built here and then moved elsewhere.
  linkEnv = pkgs.writeText "swift-link-env.sh" (
    lib.concatMapStrings (d: ''
      export LIBRARY_PATH="${d}:$LIBRARY_PATH"
      export LD_LIBRARY_PATH="${d}:$LD_LIBRARY_PATH"
    '') libDirs
    + ''
      export NIX_LDFLAGS="${lib.concatMapStrings (d: " -Wl,-rpath,${d}") libDirs} $NIX_LDFLAGS"
    ''
  );

  # `swift` and `swiftc` are front ends that exec the driver; the driver itself is
  # left untouched (it rejects compiler flags and does not need them -- the LINKER
  # is what reads LIBRARY_PATH).
  #
  # These are built with writeScript rather than a heredoc inside the runCommand:
  # a heredoc written from an indented nix string keeps its leading spaces, and a
  # shebang that is not at column 0 is not a shebang.
  mkWrapper = prog: pkgs.writeScript "swift-${prog}-wrapper" ''
    #!${pkgs.runtimeShell}
    # Put swift's runtime libraries on the link path (LIBRARY_PATH) and the run
    # path (LD_LIBRARY_PATH). See setups/swift-6.3.3.nix.
    . ${linkEnv}
    exec ${pkgs.swift}/bin/${prog} "$@"
  '';

  wrappers = pkgs.runCommand "swift-wrappers" { } (
    lib.concatMapStrings (prog: ''
      mkdir -p $out/bin
      cp ${mkWrapper prog} $out/bin/${prog}
      chmod +x $out/bin/${prog}
    '') [ "swift" "swiftc" ]
  );
in
pkgs.symlinkJoin {
  name = "swift-${pkgs.swift.version}";
  # `wrappers` is FIRST: with ignoreCollisions the first path to provide a name
  # wins, so listing it last would leave swift's own bin/swift in place (that is
  # what an earlier revision did, and the probe found an ELF binary where it
  # expected the script).
  paths = [ wrappers pkgs.swift ] ++ extraLibs;
  ignoreCollisions = true;
}
