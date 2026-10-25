# easysetup

Toolchains for CI, as prebuilt nix closures.

```yaml
- uses: easydev-org/easysetup@main
  with:
    tools: node python jq
```

That is the whole interface. Each tool arrives as a complete nix store closure,
unpacked and put on `PATH` for the following steps - no apt, no dependency
resolution, no compilation, no version pinning to maintain.

Runtimes: node, bun, deno, python, go, java, kotlin, scala, clojure, rust,
swift, clang, gcc, php, ruby, perl, r, julia, crystal, dart, elixir, erlang,
ghc, dotnet, lua, nim, opam, zig.

Build and package: cargo, bazel, cmake, ninja, meson, maven, gradle, sbt, cabal,
conan, pnpm, yarn, npm (with node), uv, pip, composer, micromamba, pixi,
luarocks, nix.

Dev tooling, one workflow per language:

| language | lint | format | LSP | test |
|---|---|---|---|---|
| TypeScript/JS | **biome** | **biome** | typescript-language-server, vscode-langservers | — |
| Python | **ruff**, pylint | **ruff** | basedpyright | pytest, coverage |
| Go | **golangci-lint** (109 linters) | gofmt (in `go`) | gopls | go test |
| Rust | **clippy** | **rustfmt** | rust-analyzer | cargo-nextest |
| C/C++ | **clang-tidy**, cppcheck | **clang-format** | **clangd** | gcovr, lcov |
| PHP | **psalm**, phpmd | **php-cs-fixer** | psalm-language-server | — |
| Ruby | **rubocop** | **rubocop -a** | ruby-lsp | rake |
| Lua | — | **stylua** | lua-language-server | — |
| JVM | pmd | google-java-format | jdtls | — |

Infra and CLI: kubectl, helm, kustomize, kind, podman, skopeo, opentofu,
awscli2, jenkins, git, gh, glab, git-lfs, curl, wget, rsync, openssh, gnupg,
zip, unzip, xz, zstd, make, shellcheck, shfmt, actionlint, yamllint, taplo,
markdownlint-cli2, pre-commit, trivy, gitleaks, hadolint, ripgrep, fd, jq, yq,
jqp, dasel, miller, protobuf, buf.

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

**No particular distribution.** The artifacts carry their own glibc: every
binary's `PT_INTERP` is an absolute `/nix/store` path inside the closure, and
`ldd` resolves `libc.so.6` from there too. The host libc is never consulted, so
its version does not matter.

Measured, running `jq` from the published artifacts:

| host | host libc | result |
|---|---|---|
| Ubuntu 24.04 | glibc 2.39 | works |
| Debian 12 | glibc 2.36 | works |
| Fedora 44 | glibc 2.43 | works |
| **Alpine** | **musl - no glibc at all** | **works** |

```yaml
jobs:
  build:
    runs-on: ubuntu-latest     # no container needed
```

What is required: `bash` and `curl`. The static binary downloads, verifies,
decompresses and unpacks in-process, so `zstd`, `python3` and `sha256sum` are no
longer needed - the action installs `curl` if the image lacks it, picking whichever
package manager is present (apt, dnf, yum, apk, zypper).

Debian-slim and Alpine ship no curl at all, so a `container:` still helps there -
but for curl, not for the libc.

**`/nix/store` must be writable, and only creating it needs root.** The action runs
`easysetup prepare`, which creates the directory as root or via sudo. Everything
after that - downloading, unpacking, installing - runs as the unprivileged user.

That matters because it is the case a container hides: root ignores permission
bits, so two installer bugs (creating 0555 directories and then filling them; and
two setups carrying the same store path, so the second could not replace the
first's read-only copy) only appeared on a plain runner. `sudo install` is
therefore neither needed nor wanted - it would paper over exactly those failures.
`tools/test-nonroot-install.sh` runs the whole install as `nobody` and is part of
CI.

## Use without the action

The action is a convenience wrapper; the binary stands alone. It is statically
linked with no interpreter, so it runs on any Linux userland - including images
with no shell and no package manager.

```bash
# fetch it however you like, then
sudo ./easysetup prepare        # creates /nix/store; the only step needing root
./easysetup install node jq     # downloads, verifies, unpacks - as your user
./easysetup env ~/env.sh        # a PATH script you can source
```

Releases are per architecture (`linux/amd64`, `linux/arm64`); take the one
matching `uname -m`. It resolves dependencies itself (see below), verifies each
tarball against the release's `SHA256SUMS`, and unpacks at `/`.

## What actually gets downloaded

A tarball does not contain its whole closure. Two things are removed first,
because someone else already supplies them:

* **the shared base** - the 8 store paths shared by most setups, glibc above all.
  Published once as `base-2.44`, subtracted from everything else.
* **anything a dependency provides** - `composer`'s closure contains `php`'s
  entirely, so composer's tarball holds only its own 6 paths and `php` is
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

## One workflow per language, not every tool that exists

The rule is one recommended tool per job. Offering black *and* ruff *and* flake8
means three ways to do the same thing and no answer to "which should I use".
Each removal was checked against the tool being kept:

| removed | because |
|---|---|
| black, isort, flake8 | `ruff format` and `ruff check` cover all three, in one fast binary |
| pyright | basedpyright is its fork; keeping both shipped the same 27 paths twice (96% measured overlap) |
| prettier, eslint | `biome check` formats and lints in one binary, `biome ci` does it non-destructively |
| gofumpt, gotools | `go` ships gofmt; golangci-lint reviews with 109 linters including staticcheck and govet |
| ccls, cpplint | clang-tools ships clangd and clang-tidy already |
| phan | psalm analyses whole programs and ships psalm-language-server |
| solargraph | ruby-lsp is the official language server |

Kept because they are not duplicates:

* **gcc and clang** - projects require one or the other; the 84% payload they
  share is glibc.
* **micromamba and pixi** - a conda-compatible CLI versus a project-based
  workflow are different models.
* **gcovr and lcov** - gcovr is the friendly front-end, lcov's `genhtml` is
  invoked directly by many C projects.
* **cppcheck** - a different analysis from clang-tidy, not a subset.

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
