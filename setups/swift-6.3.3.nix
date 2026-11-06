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
# glibc is NEVER put on a loader path, and LD_LIBRARY_PATH is not set at all: a
# directory there is inherited by every process the toolchain starts, including its
# OWN binaries, which then load the wrong copy of a library (this broke clang and
# swift-build in CI). A built program gets its run path from -rpath in its ELF.
let
  inherit (pkgs) lib;
  swift = pkgs.swift;

  # SwiftPM, which nixpkgs ships SEPARATELY from swift (`swift build` is a
  # subcommand provided by swiftpm's `swift-build`, not by pkgs.swift). Both are
  # cached derivations, so including it is still a pure assembly.
  #
  # The `only_arch = amd64` in matrix-nix.yml already keeps this setup off aarch64,
  # where nixpkgs marks swift broken.
  swiftpm = pkgs.swiftpm;
in
pkgs.runCommand "swift-${swift.version}" {
  # flake.nix's `versions` tree reads `.version` off every setup, and
  # tools/build-nixpkg.sh compares it against the name to refuse a mislabelled
  # tag. `pkgs.<attr>` has one; a runCommand does not unless it is passed here.
  inherit (swift) version;

  # Nix writes each runtime closure to its own file, one path per line,
  # formatted as "<path> <nrefs> <ref>...". Two files: swift's closure and
  # swiftpm's (which is separate and does not imply swift's).
  exportReferencesGraph = [
    "swift-runtime" swift
    "swiftpm-runtime" swiftpm
  ];
} ''
  set -euxo pipefail
  echo "=== stage: mirror ==="
  mkdir -p "$out/bin"

  # Mirror swift's output: everything as a symlink, bin/ and lib/ as REAL
  # directories because both need extra entries merged in below.
  #
  # They must be real: `ln -s` for lib and then `mkdir -p $out/lib/swift` would
  # follow the symlink into swift's read-only store path.
  mkdir -p "$out/bin" "$out/lib/swift"
  for entry in ${swift}/*; do
    name="$(basename "$entry")"
    case "$name" in
      bin)
        for f in "$entry"/*; do
          ln -s "$f" "$out/bin/$(basename "$f")"
        done
        ;;
      lib)
        for f in "$entry"/*; do
          case "$(basename "$f")" in
            swift) ;;   # merged below
            *) ln -s "$f" "$out/lib/$(basename "$f")" ;;
          esac
        done
        for f in "$entry"/swift/*; do
          ln -s "$f" "$out/lib/swift/$(basename "$f")"
        done
        ;;
      *)
        ln -s "$entry" "$out/$name"
        ;;
    esac
  done

  # SwiftPM. Two things have to come across, not just bin/:
  #
  #   bin/                      swift-build, swift-test, swift-run, ...
  #   lib/swift/pm/ManifestAPI  the PackageDescription module, plus PackagePlugin
  #
  # swiftpm patches its own "where are my API modules" lookup to
  # `applicationPath.parentDirectory` (see nixpkgs' UserToolchain.swift patch), so
  # when it runs as $out/bin/swift-build it looks in $out/lib/swift/pm/ManifestAPI.
  # Linking only bin/ makes every package fail to parse with
  #
  #   Package.swift:2:8: error: no such module 'PackageDescription'
  for f in ${swiftpm}/bin/*; do
    ln -sf "$f" "$out/bin/$(basename "$f")"
  done
  for entry in ${swiftpm}/lib/swift/*; do
    ln -sfn "$entry" "$out/lib/swift/$(basename "$entry")"
  done

  # The link/run paths, one export per directory in the runtime closure that
  # actually holds shared objects.
  #
  # `$p/lib` is not assumed: swift-foundation-icu and several other closure
  # members do not use the plain lib/ layout, and an earlier revision that tested
  # for exactly `$p/lib` silently dropped ICU, which is the whole bug. find covers
  # any depth.
  #
  # Collect into a file first. A pipeline inside $( ) would inherit `pipefail`,
  # and a single failing `find` (the graph file ends with a blank line, so the
  # loop sees an empty path and `find` exits non-zero) would then kill the whole
  # assignment with no message at all.
  : > libdirs.raw
  for graph in swift-runtime swiftpm-runtime; do
    while read -r p _rest; do
      [ -n "$p" ] || continue
      case "$p" in
        *glibc*) continue ;;
      esac
      find "$p" -maxdepth 4 -name '*.so*' -print 2>/dev/null >> libdirs.raw || true
    done < "$graph"
  done
  libdirs="$(sed 's|/[^/]*$||' libdirs.raw | sort -u)"

  # Keep the raw graphs in the output so a failing job can see WHICH store paths
  # nix actually recorded. Guessing at this from the outside cost several CI rounds.
  cat swift-runtime swiftpm-runtime > "$out/swift-runtime.txt"
  for graph in swift-runtime swiftpm-runtime; do
    while read -r p _rest; do
      [ -n "$p" ] || continue
      echo "=== $p"
      find "$p" -maxdepth 5 -name '*.so*' -print 2>/dev/null | sed 's/^/    /' || true
    done < "$graph"
  done > "$out/swift-closure-sos.txt" 2>&1 || true

  # LD_LIBRARY_PATH IS DELIBERATELY NOT SET. It is inherited by every process the
  # toolchain starts, including the toolchain's own binaries, and it made them load
  # the wrong libraries twice:
  #
  #   .../clang-21.1.8/bin/clang: symbol lookup error: undefined symbol:
  #     _ZN5clang16CompilerInstance17createDiagnosticsE...
  #   .../swift-build: symbol lookup error: libCommands.so: undefined symbol:
  #     $s11SwiftParser0B0V0A7VersionOMn
  #
  # Both were a second copy of a library in the closure winning over the one the
  # binary was built against. Filtering the list only moves the problem: the next
  # package that ships its own copy breaks the same way.
  #
  # A built program does not need it either -- `-rpath` (below) records the
  # directory in its own ELF, which is what a relocatable artifact should do.
  #
  # LIBRARY_PATH stays: it is read by the LINKER only, which opens exactly the
  # names it is asked for and never affects an already-running process.

  # ICU has to be on the LINK LINE, not merely on a search path.
  #
  # libFoundation.so records its ICU dependency as an absolute DT_NEEDED path, but
  # GNU ld does not inherit a shared library's DT_NEEDED entries
  # (--no-copy-dt-needed-entries), so a program importing Foundation fails with
  # 240 undefined `ucal_*`/`ucnv_*`/`utrans_*` symbols unless ICU is named.
  #
  # The library name is read out of libFoundation.so rather than hardcoded, so a
  # nixpkgs bump that renames it still links. `|| true` throughout: grep/sed exit
  # non-zero on no match, and under `set -o pipefail` that would abort the build
  # (which is exactly how two earlier rounds failed, with an empty log).
  icu_args=""
  if [ -e "${swift}/lib/libFoundation.so" ]; then
    icu_sos=$(${pkgs.binutils}/bin/readelf -d "${swift}/lib/libFoundation.so" 2>/dev/null \
      | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | grep -i icu || true)
    for so in $icu_sos; do
      icu_args="$icu_args -L$(dirname "$so") -l$(basename "$so" | sed 's/^lib//; s/\.so.*//')"
    done
  fi

  # easydev_rpath must exist in THIS shell before it is appended to; assigning it
  # only inside the redirect below would write the assignment into the file and
  # leave the variable unset, which `set -u` turns into an immediate exit with no
  # message at all (that is what made an earlier build fail with an empty log).
  easydev_rpath=""
  {
    echo "easydev_icu_args='$icu_args'"
    for d in $libdirs; do
      printf 'export LIBRARY_PATH="%s:$LIBRARY_PATH"\n' "$d"
      easydev_rpath="$easydev_rpath -rpath $d"
    done

    # NIX_LDFLAGS is what nixpkgs' swift WRAPPER turns into linker arguments, one
    # `-Xlinker` each. On a native build its name has no suffix (suffixSalt is
    # only set when cross-compiling), so a suffixed name is silently ignored --
    # verified by grepping the wrapper, which contains no NIX_LDFLAGS_<suffix> at
    # all on this platform. Emit both spellings; unused exports are harmless.
    for v in NIX_LDFLAGS NIX_LDFLAGS_x86_64_unknown_linux_gnu; do
      printf 'export %s="%s $easydev_icu_args $%s"\n' "$v" "$easydev_rpath" "$v"
    done
    echo 'unset easydev_rpath easydev_icu_args'
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
      printf '%s\n' '# and on the built program'"'"'s RUN path (via -rpath in its ELF).'
      printf '%s\n' '# See setups/swift-6.3.3.nix.'
      # Expanded HERE, at build time: the script needs the real store path.
      printf '%s\n' ". $out/swift-link-env.sh"
      # `swift build` is a swift-DRIVER subcommand: the driver execs `swift-build`
      # from PATH. Without this, a consumer that copies the store path and runs
      # $out/bin/swift directly (a Dockerfile, an editor plugin) gets
      #
      #   error: unknown or missing subcommand 'swift-build'
      #
      # even though the file is right next to the compiler.
      printf 'PATH="%s/bin:$PATH"; export PATH\n' "$out"
      # The original entry point is a symlink whose NAME the driver reads, so it
      # is exec'd by path, not by its resolved target.
      printf 'exec %s "$@"\n' '${swift}/bin/'"$prog"
    } > "$out/bin/$prog"
    chmod +x "$out/bin/$prog"
  done
''
