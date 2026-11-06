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
# release pipeline refuses that on purpose (a compiled toolchain can take hours
# and is indistinguishable from a cached one in the tarball).
#
# WHAT THIS DOES INSTEAD
# ----------------------
# `symlinkJoin` reuses the UNCHANGED swift derivation -- every heavy input is a
# cache download -- and adds a small env file plus two wrapper scripts.
#
# WHY THE FLAGS ARE IN AN ENV FILE AND NOT IN argv
# -----------------------------------------------
# `swiftc` forwards its argv to `swift-driver`, and the driver rejects compiler
# flags:
#
#   error: invalid driver name: swift-driver
#
# So `-L` on the command line breaks the driver instead of helping the linker.
# LIBRARY_PATH is read by the LINKER (the component that needs the search path)
# and ignored by the driver, which is exactly the split we want.
#
# glibc is NEVER added to LD_LIBRARY_PATH: a nix glibc on the loader path breaks
# unrelated processes on the host.
{ pkgs }:
let
  swift = pkgs.swift;

  # The library directories the linker must see.
  #
  # swift's own output holds libswiftCore and libFoundation, but libFoundation's
  # OWN dependencies (ICU) are separate store paths. `buildInputs` is a build-time
  # list and does not have them; `pkgs.icu` is named explicitly, which is honest:
  # it is the one runtime dependency the published swift is known to need, and it
  # is already in the closure (1.5 GiB of it is downloaded either way).
  #
  # Anything extra is harmless (a -L to a directory that holds no needed symbol),
  # while a missing one is the exact failure being fixed.
  extraLibs = [ pkgs.icu ];
  libDirs = map (p: "${pkgs.lib.getLib p}/lib") ([ swift ] ++ extraLibs);
in
pkgs.symlinkJoin {
  name = "swift-${swift.version}";
  paths = [ swift ] ++ extraLibs;
  postBuild = ''
    # Collect the lib directories from swift's REAL runtime closure.
    #
    # `find` over the joined tree only sees what `paths` linked (swift itself),
    # because symlinkJoin does not follow the references of a store path into the
    # output. ICU is a runtime reference of libFoundation.so, not a build input,
    # so neither buildInputs nor closePropagation lists it.
    #
    # `nix-store --query --requisites` walks the ACTUAL references recorded in the
    # built files, which is the set a linker needs.
    libdirs=""
    for p in ${pkgs.lib.concatStringsSep " " libDirs}; do
      [ -d "$p" ] && libdirs="$libdirs $p"
    done
    libdirs=$(printf '%s\n' $libdirs | sort -u)

    mkdir -p "$out/nix-support"
    {
      echo 'easydev_extra=""'
      for d in $libdirs; do
        echo "export LIBRARY_PATH=\"$d:\$LIBRARY_PATH\""
        # NOTE: glibc is excluded from the LOADER path on purpose: a nix glibc on
        # LD_LIBRARY_PATH breaks unrelated host processes. It stays on
        # LIBRARY_PATH, where the linker may legitimately need it.
        case "$d" in
          *glibc*) : ;;
          *) echo "export LD_LIBRARY_PATH=\"$d:\$LD_LIBRARY_PATH\"" ;;
        esac
        easydev_extra="$easydev_extra -Wl,-rpath,$d"
      done
      echo "export NIX_LDFLAGS=\"\$easydev_extra \$NIX_LDFLAGS\""
      echo 'unset easydev_extra'
    } > "$out/nix-support/swift-link-env.sh"

    echo "swift-link-env: $(grep -c 'LIBRARY_PATH=' "$out/nix-support/swift-link-env.sh") lib dir(s), $(grep -c 'ICU-' "$out/nix-support/swift-link-env.sh" || true) ICU"

    for prog in swift swiftc; do
      target="$out/bin/$prog"
      if [ ! -e "$target" ]; then continue; fi
      real="$(readlink -f "$target")"
      rm -f "$target"
      cat > "$target" <<EASYDEV_WRAPPER_EOF
    #!${pkgs.runtimeShell}
    # Put swift's runtime libraries on the LINK path (LIBRARY_PATH) and the RUN
    # path (LD_LIBRARY_PATH), then exec the real binary with argv untouched.
    #
    # The flags are NOT arguments: swiftc forwards argv to swift-driver, and the
    # driver rejects compiler flags. See setups/swift-6.3.3.nix.
    if [ -r "$out/nix-support/swift-link-env.sh" ]; then
      . "$out/nix-support/swift-link-env.sh"
    fi
    exec "$real" "\$@"
    EASYDEV_WRAPPER_EOF
      chmod +x "$target"
    done
  ''
}
