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
# ONE small derivation that symlinks the UNCHANGED swift output into place and
# overrides two entry points with scripts. Every heavy input is still a cache
# download; the local work is a loop of `ln` and two `printf`s.
#
# WHY ONE DERIVATION AND NOT A symlinkJoin OF SEVERAL
# --------------------------------------------------
# The release gate allows a setup to be assembled locally ONLY when the sole path
# to build is the setup's own derivation. Extra helper derivations (a writeText
# for the env file, a runCommand for the wrappers) would be separate paths, and
# the gate would - correctly - refuse them as unexplained local builds.
#
# WHERE THE LIBRARY LIST COMES FROM
# ---------------------------------
# `exportReferencesGraph` makes nix write swift's real RUNTIME closure into the
# build directory. That is the only honest source: `buildInputs` is a build-time
# list and does not contain the runtime dependencies, and naming `pkgs.icu` by
# hand is wrong too -- the ICU swift links against is `swift-foundation-icu`
# (76142.4.7), not nixpkgs' icu4c. Naming the wrong one leaves the undefined
# symbols in place.
#
# WHY THE FLAGS ARE ENV AND NOT argv
# ---------------------------------
# `bin/swiftc` is a symlink to `bin/swift-driver`, which picks its mode from
# argv[0]. Exec'ing the resolved `swift-driver` path makes it fail with
#
#   error: invalid driver name: swift-driver
#
# so the wrappers must exec the ORIGINAL symlink (`.../bin/swiftc`), not its
# target. Keeping the flags out of argv also keeps them out of the way: the
# linker reads LIBRARY_PATH, the driver ignores it.
#
# glibc is NEVER added to LD_LIBRARY_PATH: a nix glibc on the loader path breaks
# unrelated processes on the host.
let
  inherit (pkgs) lib;
  swift = pkgs.swift;
in
pkgs.runCommand "swift-${swift.version}" {
  # Nix writes every path in swift's runtime closure to ./swift-runtime, one per
  # line, formatted as "<path> <nrefs> <ref>...".
  exportReferencesGraph = [ "swift-runtime" swift ];
} ''
  set -euxo pipefail
  echo "=== stage: mirror ==="
  mkdir -p "$out/bin"

  # Mirror swift's output: everything as a symlink, bin/ file by file so the two
  # entry points can be replaced below.
  for entry in ${swift}/*; do
    name="$(basename "$entry")"
    if [ "$name" = bin ]; then
      for f in "$entry"/*; do
        ln -s "$f" "$out/bin/$(basename "$f")"
      done
    else
      ln -s "$entry" "$out/$name"
    fi
  done

  # The link/run paths, one export per directory in the runtime closure that
  # actually holds shared objects.
  #
  # `$p/lib` is not assumed: swift-foundation-icu and several other closure
  # members do not use the plain lib/ layout, and an earlier revision that tested
  # for exactly `$p/lib` silently dropped ICU, which is the whole bug. find covers
  # any depth.
  #
  # glibc is skipped: on LD_LIBRARY_PATH it breaks unrelated host processes, and
  # the compiler already reaches it through the toolchain.
  #
  # The list is deduplicated because a closure member can appear more than once,
  # and a path repeated once per occurrence makes the env file unreadable when it
  # is printed by a failing job.
  # Collect into a file first. A pipeline inside $( ) would inherit `pipefail`,
  # and a single failing `find` (a blank line in the graph file makes `find ''`
  # exit non-zero) would then kill the whole assignment with no message.
  : > libdirs.raw
  while read -r p _rest; do
    [ -n "$p" ] || continue
    case "$p" in
      *glibc*) continue ;;
    esac
    find "$p" -maxdepth 4 -name '*.so*' -print 2>/dev/null >> libdirs.raw || true
  done < swift-runtime
  libdirs="$(sed 's|/[^/]*$||' libdirs.raw | sort -u)"

  # easydev_rpath must exist in THIS shell before it is appended to; assigning it
  # only inside the redirect below would write the assignment into the file and
  # leave the variable unset, which `set -u` turns into an immediate exit with no
  # message at all (that is what made an earlier build fail with an empty log).
  easydev_rpath=""
  {
    echo 'easydev_rpath=""'
    for d in $libdirs; do
      printf 'export LIBRARY_PATH="%s:$LIBRARY_PATH"\n' "$d"
      printf 'export LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\n' "$d"
      easydev_rpath="$easydev_rpath -Wl,-rpath,$d"
    done
    printf 'export NIX_LDFLAGS="%s $NIX_LDFLAGS"\n' "$easydev_rpath"
    echo 'unset easydev_rpath'
  } > "$out/swift-link-env.sh"

  echo "swift-link-env: $(grep -c LIBRARY_PATH "$out/swift-link-env.sh") lib dir(s)"

  # The wrappers. The body is emitted with printf rather than a heredoc inside
  # this indented nix string: those keep their leading spaces, and a shebang that
  # is not at column 0 is not a shebang.
  for prog in swift swiftc; do
    # -f matters: bin/$prog is a symlink into the store, and a redirection would
    # follow it and try to write into the read-only store path.
    rm -f "$out/bin/$prog"
    {
      printf '%s\n' '#!${pkgs.runtimeShell}'
      printf '%s\n' '# Put swift'"'"'s runtime libraries on the LINK path (LIBRARY_PATH)'
      printf '%s\n' '# and on the RUN path (LD_LIBRARY_PATH). See setups/swift-6.3.3.nix.'
      # Expanded HERE, at build time: the script needs the real store path.
      printf '%s\n' ". $out/swift-link-env.sh"
      # The original entry point is a symlink whose NAME the driver reads, so it
      # is exec'd by path, not by its resolved target.
      printf 'exec %s "$@"\n' '${swift}/bin/'"$prog"
    } > "$out/bin/$prog"
    chmod +x "$out/bin/$prog"
  done
''
