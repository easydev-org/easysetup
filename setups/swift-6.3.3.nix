# HAND-EDITED, deliberately without the "Generated" marker so gen-setups.py
# leaves it alone. The override is not cosmetic: without it `swiftc` cannot
# link anything.
#
# nixpkgs builds swift with its runtime libraries in `$out/lib` but compiles a
# search path of `$out/lib/swift/linux` into the driver, and that directory holds
# only .swiftmodule files. So `swiftc main.swift -o app` fails with
#
#   ld.bfd: cannot find -lswiftCore: No such file or directory
#
# while libswiftCore.so is sitting in `$out/lib`, 10 MB of it. Upstream knows the
# rpath is wrong - `$out/nix-support/setup-hook` defines fixSwiftRpathsIn() - but
# that only runs inside a nix build's fixup phase, never when a user calls swiftc
# directly.
#
# `NIX_LDFLAGS` is not enough (it is only read by the cc wrapper), so the fix is a
# wrapper that appends -L to compiler invocations. `swift`, `swiftc` and
# `swift-driver` all go through the same driver, and all three need it.
{ pkgs }:
let
  swift = pkgs.swift;
  lib = "${swift}/lib";
in
swift.overrideAttrs (old: {
  # A postBuild would not help: the whole point is that the shipped binary must
  # differ from the one nixpkgs ships.
  postInstall = (old.postInstall or "") + ''
    for prog in swift swiftc swift-driver; do
      target="$out/bin/$prog"
      [ -e "$target" ] || continue
      mv "$target" "$target.real"
      cat > "$target" <<EOF
    #!${pkgs.runtimeShell}
    # Adds the runtime library directory that nixpkgs leaves out of the driver's
    # search path. See the comment in setups/swift-6.3.3.nix.
    exec "\$(dirname "\$0")/$prog.real" -L${lib} "\$@"
    EOF
      chmod +x "$target"
    done
  '';
})
