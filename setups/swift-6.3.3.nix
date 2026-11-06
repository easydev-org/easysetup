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
in
pkgs.symlinkJoin {
  name = "swift-${swift.version}";
  paths = [ swift ];
  postBuild = ''
    # Collect the lib directories from the JOINED TREE, not from a nix-level
    # dependency list: `buildInputs` is a build-time list and does not contain
    # ICU, and `closePropagation` only follows propagated inputs. What actually
    # matters is which .so files are reachable once everything is linked into
    # this one tree, so `find` over the output is the honest source.
    libdirs=$(cd "$out" && find -L . -name '*.so' -o -name '*.so.*' 2>/dev/null \
      | sed 's|^\./||; s|/[^/]*$||' | sort -u)

    mkdir -p "$out/nix-support"
    {
      echo 'easydev_extra=""'
      for d in $libdirs; do
        abs="$out/$d"
        echo "export LIBRARY_PATH=\"$abs:\$LIBRARY_PATH\""
        # NOTE: no glibc. A nix glibc on the loader path breaks the host's own
        # programs; the linker does not need it and a built binary gets glibc from
        # the program that runs it.
        case "$abs" in
          *-glibc-*|*/glibc-*) : ;;
          *) echo "export LD_LIBRARY_PATH=\"$abs:\$LD_LIBRARY_PATH\"" ;;
        esac
        easydev_extra="$easydev_extra -Wl,-rpath,$abs"
      done
      echo "export NIX_LDFLAGS=\"\$easydev_extra \$NIX_LDFLAGS\""
      echo 'unset easydev_extra'
    } > "$out/nix-support/swift-link-env.sh"

    echo "swift-link-env.sh exports $(grep -c 'LIBRARY_PATH=' "$out/nix-support/swift-link-env.sh") lib dir(s)"

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
  '';
}
