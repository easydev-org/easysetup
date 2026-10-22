# easysetup

Prebuilt toolchains for CI, installed into `/opt/setup`.

**One entry per (tool, version).** No combination images: a job that needs node
*and* python installs two entries, and each lands in its own directory.

```bash
./install.sh --list
./install.sh node-22.23.4 python-3.12.15
./install.sh node-22                     # -> node-22.23.4
```

### Names are resolved, not required to be exact

A setup name may be a **prefix of the version**, matched by dot-separated
segment, and when several entries match the **newest** wins:

| you write | you get |
|---|---|
| `node-22` | `node-22.23.4` (newest 22.x published) |
| `node-22.23` | `node-22.23.4` |
| `node-22.23.4` | `node-22.23.4` (exact always wins) |
| `python-3` | the newest 3.x |

Matching is by **whole segments**, not characters: `node-2` does **not** match
`node-22.23.4`, because `2` is not a segment of `22`. A character-prefix rule
would silently install the wrong major version, so it is refused instead.

A bare `rust-1.99.1` resolves to the **host** toolchain. Cross-compilation
support is an optional **component**, named with `@`:

| you write | you get |
|---|---|
| `rust-1.99.1` | the host toolchain |
| `rust-1.99.1@x86_64-pc-windows-gnu` | host + that component |
| `rust-1@x86_64-pc-windows-gnu` | version prefix also works |

**A component must be spelled in full** — `@windows-gnu`, `@x86_64` and
`@gnu` are all refused rather than guessed at, because a wrong guess costs a
full toolchain download.

## requires: dependencies, with optional version ranges

`requires` names setups that must be installed first. A requirement may pin an
exact setup, name a version line, or give a range - all resolved against what
the manifest actually publishes:

| you write | you get |
|---|---|
| `erlang-29.1.2` | exactly that setup |
| `erlang-29` | that tool, newest 29.x |
| `erlang@>=29 <30` | any 29.x (newest wins) |
| `erlang@>=29,<30` | the same, comma-separated |
| `erlang` | newest of that tool |

The `@` separates the tool from the constraint, so `erlang-29` (a version
prefix) and `erlang@>=29` (a range) are never confused.

**A requirement that matches nothing is an error**, and the message names what
is published:

```
requires 'erlang@>=99': no erlang satisfies '>=99' (published: 29.1.2, 29.0.1)
```

That matters: a dependency that silently resolved to nothing would install the
dependent with no runtime at all, and fail much later and far from the cause.

`matrixlib.py plan <name>` shows the resolution with dependencies marked:

```
erlang-29.1.2  (required)
elixir-1.20.4
```
## The install contract

For every entry, installing is exactly:

1. `apt-get install` the entry's `apt_deps` (shared libraries only),
2. download the **one** prebuilt tarball the entry names,
3. verify its `sha256`,
4. unpack it at `/`.

**Nothing is compiled — not at install time, and not when the release is cut
either.** Every toolchain comes from an upstream *prebuilt* distribution:

| tool | prebuilt source |
|---|---|
| node, python, go, java | vendor official tarballs |
| maven, gradle, helm, bazel, dotnet | vendor official distributions |
| rust | rust-lang's own component tarballs (unpacked, not built) |
| php | `shivammathur/php-builder`, a **debian 13** build — exact platform match |
| ruby | `ruby/ruby-builder`, the tarball behind `ruby/setup-ruby` |

`./selftest.sh` fails if a build script ever gains `./configure`, `make` or
`cmake`, or if `install.sh` grows a step that needs the network.

## Usage

```yaml
# .easy-platform/ci.yml
version: 1
on: [rr_opened, rr_synced]
jobs:
  test:
    image: debian:trixie
    setup: [node-22.23.4, python-3.12.15]
    commands:
      - . /opt/setup/env.sh
      - node --version && python3 --version
```

### Two versions of one tool

```yaml
    setup: [node-22.23.4, node-24.22.1]
    commands:
      - . /opt/setup/env.sh
      - node --version                          # 24 — last on the list wins PATH
      - /opt/setup/node-22.23.4/bin/node -v     # 22, by absolute path
```

## Layout

```
/opt/setup/node-22.23.4/bin/node
/opt/setup/node-24.22.1/bin/node     <- coexist
/opt/setup/java-21.0.12+101/bin/java
/opt/setup/env.sh                    <- written by install.sh
```

The directory name is **derived** (`<tool>-<version>`), never stored in the
manifest — there is no second place to keep in sync. `env.sh` also exports
`JAVA_HOME` for the last java installed.

## matrix.yml

`setups` is a **list**; `version` is its own field:

```yaml
setups:
  - tool: node
    version: "22.23.4"
    apt_deps: [ca-certificates, curl, xz-utils, libatomic1]
    artifact: node-22.23.4-debian-trixie-amd64.tar.xz
    sha256: "…"          # written by the release workflow
```

| field | meaning |
|---|---|
| `tool` | which build script installs it (`tools/build-<tool>.sh`) |
| `version` | the exact upstream version, pinned by hand |
| `target` | optional, for a cross-compilation toolchain (rust) |
| `apt_deps` | base packages installed with apt before unpacking |
| `artifact` | the release asset carrying the complete tree |
| `sha256` | checksum; `install.sh` refuses to unpack on mismatch |

`matrixlib.py` is the only parser. `install.sh`, `bump.py`, the release
workflow and `selftest.sh` all go through it, so they cannot disagree about what
an entry is called.

## What is published

| tool | versions | notes |
|---|---|---|
| `node` | 22.23.4, 24.22.1, 26.12.1 | |
| `python` | 3.12.15, 3.13.17, 3.14.9, 3.15.1 | |
| `go` | 1.24.13, 1.25.14, 1.26.10, 1.27.3 | |
| `java` | 17.0.20+101, 21.0.12+101, 25.0.4+101, 27.0.0+35 | Temurin JDK |
| `maven` | 3.10.0 | needs a `java-*` beside it |
| `gradle` | 9.8.2, 8.14.6 | needs a `java-*` beside it |
| `ruby` | 4.0.8, 3.4.11 | prebuilt (ubuntu tarball; glibc is backward compatible) |
| `rust` | 1.99.1 | rustc + cargo + host std; **no rustup** |
| `rust` +`x86_64-pc-windows-gnu` | 1.99.1 | cross-compiles real .exe via mingw |
| `rust` +`x86_64-pc-windows-msvc` | 1.99.1 | std only — `cargo check`, not linking |
| `dotnet` | 10.0.402 | LTS |
| `php` | 8.5 | prebuilt for debian 13; the value is php-builder's release line |
| `helm` | 4.3.1 | |
| `bazel` | 9.3.1 | needs a JRE (`openjdk-21-jre-headless` in apt_deps) |
| `buf` | 1.75.0 | |

**Platform: debian trixie, amd64.**

## rust is different, on purpose

A rust toolchain is ~379 MB per version, so there is no `rust-<v>` set of
images like the other tools. Instead:

- `rust-1.99.1` — the host toolchain: `rustc` + `cargo` + the host `rust-std`,
  merged from the three upstream components into one tree.
- `rust-1.99.1+x86_64-pc-windows-gnu` — the Windows GNU std, for cross-compiling
  a real `.exe` from linux (mingw is in `apt_deps`).
- `rust-1.99.1+x86_64-pc-windows-msvc` — std only. Linking needs MSVC on
  Windows, so on linux this supports `cargo check`, not a finished binary.

`rustup` is never involved: components are unpacked directly.

## Releases

**Both workflows are `workflow_dispatch` only — there is no `push:` trigger.**

A push trigger fires once per commit, and this repository is edited through the
GitHub contents API, which creates **one commit per file**. A 25-file change
therefore started 25 runs, each fanning out to 28 build jobs; hundreds of jobs
queued behind the account's concurrency limit and nothing finished. Publishing
artefacts is an explicit act anyway.

To rebuild everything, or just one entry:

```bash
gh workflow run release.yml                          # all entries
gh workflow run release.yml -f only=node-22.23.4     # one entry
gh workflow run refresh.yml                          # check for newer upstream versions
```

One release per entry, tagged with the derived directory name:

```
releases/download/node-22.23.4/node-22.23.4-debian-trixie-amd64.tar.xz
```

`.github/workflows/release.yml` builds each inside `debian:trixie`, runs an
`ldd` check on every ELF (a missing entry in `apt_deps` fails the build rather
than shipping a broken tarball), publishes, and commits the resulting `sha256`
back into `matrix.yml` — editing the *latest* main so a long build cannot lose
the race with another push.

## Keeping pins current

```bash
python3 tools/bump.py --check     # exit 1 if any pin is behind upstream
python3 tools/bump.py --apply
```

Each entry tracks its own line, derived from its pinned version: `node 22.23.4`
follows 22.x, `python 3.12.15` follows 3.12.x. Bumping rewrites the version and
the artifact name and **clears the sha256**; the release workflow re-pins it.

`.github/workflows/refresh.yml` runs the check weekly and opens a **pull
request** with the diff. It never pushes to main: a bump changes the runtime
every consuming pipeline gets.

## Checking it without building

```bash
./selftest.sh
```

Covers: the manifest parses, directories derive from fields, `install.sh` has no
build/network step, `bump.py` rewrites one version without touching siblings and
refuses a malformed block, `pin-checksums.sh` writes into the matching entry,
and the workflows are valid YAML that uses the list shape.
