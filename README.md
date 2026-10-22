# easysetup

Prebuilt toolchains for easydev CI, installed on demand into `/opt/setup`.

**One setup per (tool, version). No combinations.** A job that needs node *and*
python installs two setups; each extracts into its own versioned directory, so
nothing collides. Combining them is the consumer's business.

```bash
./install.sh node-22                 # /opt/setup/node-22
./install.sh node-22 python-312      # both, side by side
./install.sh --list                  # what exists
```

## What is published

| setup id | version | source |
|---|---|---|
| `node-22` / `node-24` / `node-26` | 22.23.4 / 24.22.1 / 26.12.1 | nodejs.org dist (linux-x64) |
| `python-312` / `-313` / `-314` / `-315` | 3.12.15 / 3.13.17 / 3.14.9 / 3.15.1 | astral-sh/python-build-standalone |
| `go-124` / `-125` / `-126` / `-127` | 1.24.13 / 1.25.14 / 1.26.10 / 1.27.3 | go.dev/dl |
| `java-17` / `-21` / `-25` / `-27` | 17.0.20+101 / 21.0.12+101 / 25.0.4+101 / 27.0.0+35 | Adoptium Temurin |

**Platform: debian trixie, amd64 only.**

## How a CI job uses it

```yaml
# .easy-platform/ci.yml
version: 1
on: [rr_opened, rr_synced]
jobs:
  test:
    image: debian:trixie
    setup: [node-22, python-312]
    commands:
      - . /opt/setup/env.sh
      - node --version && python3 --version
      - npm ci && pytest
```

### Two versions of the same tool

```yaml
    setup: [node-22, node-24]
    commands:
      - . /opt/setup/env.sh
      - node --version                   # 24 (last on the list wins PATH)
      - /opt/setup/node-22/bin/node -v   # 22, addressable by absolute path
```

Both are installed; `env.sh` prepends them in the order given, so the last one
wins `PATH`. The other stays reachable by its absolute path.

## Layout

```
/opt/setup/node-22/bin/node
/opt/setup/node-24/bin/node      <- coexist
/opt/setup/python-312/bin/python3
/opt/setup/java-21/
/opt/setup/env.sh                <- written by install.sh
```

The tarball's root is `opt/setup/<id>/...`, so it extracts at `/` with no
special flags. `env.sh` exports `JAVA_HOME` for the last java installed.

## distro support

**debian trixie, amd64.** The assets are built inside `debian:trixie` and
contain binaries linked against trixie's glibc; they expect trixie's shared
libraries at run time. `install.sh` fails on a non-debian host rather than
installing something subtly broken.

The apt layer installs only the *shared libraries* a tool needs
(`ca-certificates`, `libssl3`, ... - see `apt_deps` in `matrix.yml`). The tool
itself is never an apt package, so its version is exactly the pin.

## matrix.yml is the authority

```yaml
setups:
  node-22:
    tool: node
    version: "22.23.4"
    apt_deps: [ca-certificates, curl, xz-utils]
    artifact: node-22.23.4-debian-trixie-amd64.tar.xz
    sha256: "…"            # written by the release workflow
```

| field | meaning |
|---|---|
| `tool` | which build script installs it (`tools/build-<tool>.sh`) |
| `version` | hand-pinned upstream version - never "latest" |
| `apt_deps` | base packages installed with apt before unpacking |
| `artifact` | the release asset carrying the complete tree |
| `sha256` | checksum; `install.sh` refuses to unpack on mismatch |

## Releases

One release per setup id + version:

```
releases/download/node-22-22.23.4/node-22.23.4-debian-trixie-amd64.tar.xz
```

`.github/workflows/release.yml` builds each inside `debian:trixie`, unpacks it
in a clean directory and **runs the tool**, then publishes and commits the
resulting `sha256` back into `matrix.yml`.

## Adding a version

Append to `setups:` in `matrix.yml` with a new id, version and artifact name,
leave `sha256: ""`. Commit. The workflow builds and publishes it and fills the
checksum. Adding a *tool* means also adding `tools/build-<tool>.sh`.

A pinned version is deliberate: a CI that silently upgrades runtimes breaks
builds nobody touched.

## Keeping the pins current

`tools/bump.py` compares every setup against its own upstream release line and
reports anything stale:

```bash
python3 tools/bump.py --check     # exit 1 if any pin is behind
python3 tools/bump.py --apply     # rewrite matrix.yml
```

Each id tracks only its own line, so `node-22`, `node-24` and `node-26` never
overwrite each other:

| id | tracks |
|---|---|
| `node-22` | newest `22.x` |
| `python-312` | newest `3.12.x` |
| `go-124` | newest `1.24.x` |
| `java-17` | newest `17` GA |

A bump rewrites the version **and the artifact name** (the asset carries the
version) and **clears `sha256`**, because the old digest cannot match a
different file. The release workflow re-pins it once the new asset is built, so
`install.sh` never unpacks something it cannot verify.

`.github/workflows/refresh.yml` runs `--check` weekly and, when something is
stale, runs `--apply` and opens a **pull request** with the diff. It never
pushes to main: a bump changes the runtime every consuming CI pipeline gets.

The rewrite rules have offline tests (`tools/test_bump.py`, run by
`./selftest.sh`): bumping one id must leave its siblings untouched, and a
malformed block must fail the whole file rather than half-write it.
