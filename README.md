# easysetup

Toolchains for Debian 13 CI, as prebuilt nix closures.

```yaml
- uses: easydev-org/easysetup@main
  with:
    tools: node python jq
```

That is the whole interface. Each tool arrives as a complete nix store closure,
unpacked and put on `PATH` for the following steps - no apt, no dependency
resolution, no compilation, no version pinning to maintain.

Supported: node, python, go, java, rust, cargo, swift, clang, php, ruby, perl,
r, julia, crystal, dart, deno, elixir, erlang, ghc, dotnet, lua, nim, opam, zig,
bazel, cmake, ninja, maven, gradle, sbt, cabal, conan, micromamba, pixi, luarocks,
pip, virtualenv, black, ruff, mypy, pytest, composer, php-cs-fixer, psalm, phpmd,
phing, box, kubectl, opentofu, helm, jenkins, shellcheck, ripgrep, fd, jq, yq,
git-lfs, protobuf, buf, nix.

## Why this exists

The usual CI toolchain install is `apt install`, `curl | tar`, or a language's
own version manager. Each of those reconstructs, at run time, a decision that
ought to have been made once: which versions, which system libraries, which
patches. The work is repeated on every job and every machine.

Here that work happens once, in a workflow, and its result is a tarball. nix
already knows a package's exact closure - the transitive set of store paths it
needs - so "which system libraries" is answered by the package manager rather
than by a hand-maintained list that goes stale.

## Requirements

Debian 13 (trixie). The artifacts are built against its glibc 2.41 and carry
absolute `/nix/store` interpreter paths, so they cannot run on an older libc. The
action checks this up front and refuses rather than installing 300 MB of
unusable files.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container: debian:trixie-slim     # the one requirement
```

## Use without the action

The action is a convenience wrapper; the script stands alone.

```bash
curl -fsSL https://raw.githubusercontent.com/easydev-org/easysetup/main/install.sh | bash -s -- node jq
```

Needs `curl`, `zstd`, `python3` and CA certificates. It resolves dependencies
itself (see below), verifies each tarball's SHA-256 against one published beside
it, and unpacks at `/`.

## What actually gets downloaded

A tarball does not contain its whole closure. Two things are removed first,
because someone else already supplies them:

* **the shared base** - the ~15 store paths that most setups need, glibc above
  all. Published once as `base-2.44`, subtracted from everything else.
* **anything a dependency provides** - `composer`'s closure contains `php`'s
  entirely, so composer's tarball holds only its own 14 paths and `php` is
  fetched separately.

Measured, on the published artifacts:

| setup | alone | with the scheme |
|---|---|---|
| `jq` | 11.4 MB | **0.4 MB** |
| `psalm` (a php tool) | 78 MB | **5.5 MB** |
| `pip` | ~85 MB | **3.2 MB** |
| `composer` | 78 MB | **34 MB** |

The dependency graph is not written down anywhere. `tools/compute-deps.py` reads
it from nix: a setup depends on another when the other's closure is a strict
subset of its own AND the other's output is reachable from its output at run
time (`nix why-depends`). That second test matters - without it, `dotnet`
appears to depend on `perl`, because perl was needed to *build* it.

`install.sh` then installs dependencies first. `tools: composer` gets you php
without naming it:

```
--> base-2.44  (required by composer-2.10.3)
--> php-8.5.11 (required by composer-2.10.3)
==> composer-2.10.3
```

## Package managers need a venv

`pip install` against this python fails with `externally-managed-environment`.
That is PEP 668 working as intended, not a defect: the interpreter is in the
read-only `/nix/store`. Use `python3 -m venv`. See [docs/pip.md](docs/pip.md) for
what is happening and the four options.

## Things that are deliberately absent

* **conda** - nixpkgs' `conda` is a bubblewrap FHS sandbox whose only executable
  is `conda-shell`; it does not start in an Actions container at all. `micromamba`
  and `pixi` are here instead, with `micromamba create -n x python=3.12` working
  as expected.
* **terraform** - BUSL-licensed, and Hydra does not build unfree packages, so
  every build would compile it. `opentofu` (command `tofu`) is the cached MPL
  fork.
* **swift's wasm / static-linux / android SDKs, rust's cross toolchains,
  jenkins-plugin-manager** - there is no nixpkgs attribute for them. They were
  buildable when upstream tarballs were assembled by hand; a closure-based
  pipeline cannot invent an attribute that does not exist.
* **python 3.15** - `python315Packages.*` is not in the binary cache at our pin,
  so every setup would compile from source. 3.14 is, and is one minor behind.

## Adding a setup

One line in `matrix-nix.yml`:

```yaml
- { tool: ripgrep, attr: "nixpkgs#ripgrep", version: "15.2.0" }
```

Then:

```bash
tools/gen-setups.py                                    # setups/<name>.nix
# run the compute-closures workflow                    # closures.json
# run the release workflow                             # build + publish
```

`gen-setups.py` writes `setups/<dir>.nix` containing `pkgs.<attr>`. If a package
needs its `bin` output named explicitly - `jq` and `shellcheck` both default to
their `man` output, which produces a binary-less tarball - delete the "Generated"
line from that file and it will be left alone on regeneration.

## Verifying a release

Every release carries `<name>-debian-trixie-amd64.tar.zst` and a `.sha256`
computed by the publishing job from the file it is about to upload, so the
checksum cannot describe a tarball that was never produced. The build job also
unpacks each tarball into an empty chroot and runs the binary there, which is the
only way to catch a delta that subtracted something it needed.

## Layout

| path | what |
|---|---|
| `matrix-nix.yml` | the manifest: one line per setup |
| `setups/*.nix` | generated; one nixpkgs attribute each |
| `closures.json` | generated: base set, derived dependencies, per-setup paths |
| `install.sh` | resolver + downloader + unpacker |
| `action.yml` | the composite action |
| `tools/compute-deps.py` | derives the dependency graph from nix closures |
| `tools/build-nixpkg.sh` | builds one setup into a tarball |
| `flake.nix` / `flake.lock` | pinned nixpkgs; the lock is what makes a rebuild reproducible |
