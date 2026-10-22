# easysetup

Prebuilt toolchains for easydev CI, installed on demand into `/opt/setup`.

**One setup per tool. No combinations.** A job that needs node *and* python
installs two setups; they do not conflict because each lives in its own
directory. Combining them is the consumer's business, not this repository's.

```bash
./install.sh node                    # /opt/setup/node
./install.sh node python             # both, stacked
```

## How a CI job uses it

```yaml
# .easy-platform/ci.yml
version: 1
on: [rr_opened, rr_synced]
jobs:
  test:
    image: debian:trixie
    setup: [node, python]            # two setups, installed in order
    commands:
      - . /opt/setup/env.sh
      - node --version && python3 --version
      - npm ci && pytest
```

The platform runs `install.sh node python` before `commands`. Nothing is
compiled and no version is resolved at run time: each asset is a prebuilt tree
whose version was pinned when the release was cut.

## What a setup contains

```
/opt/setup/node/bin/node
/opt/setup/node/lib/...
/opt/setup/node/...
/opt/setup/env.sh          <- written by install.sh; prepends what was installed
```

The tarball's root is `opt/setup/<tool>/...`, so it extracts at `/` with no
special flags and no knowledge of this repository's layout.

## distro support

**debian trixie, amd64 only.** The assets are built inside `debian:trixie` and
contain binaries linked against trixie's glibc; they expect trixie's shared
libraries at run time. `install.sh` refuses to run on a non-debian host. Other
distros would need their own build, not a rebuild of this one.

The apt layer installs only the *shared libraries* a tool needs
(`ca-certificates`, `libssl3`, `zlib1g`, ... - see `apt_deps` in `matrix.yml`).
The tool itself is never an apt package, so its version is exactly the pin.

## matrix.yml is the authority

```yaml
setups:
  node:
    version: "22.20.0"
    apt_deps: [ca-certificates, curl, xz-utils]
    artifact: node-22.20.0-debian-trixie-amd64.tar.xz
    sha256: "…"            # written by the release workflow
```

| field | meaning |
|---|---|
| `version` | hand-pinned upstream version - never "latest" |
| `apt_deps` | base packages installed with apt before unpacking |
| `artifact` | the release asset carrying the complete `/opt/setup/<tool>` tree |
| `sha256` | asset checksum; `install.sh` refuses to unpack on mismatch |

`install.sh` reads this file at run time, so the version it installs is the one
in the release - not a moving target.

## Releases

One release per tool+version:

```
https://github.com/easydev-org/easysetup/releases/download/node-22.20.0/node-22.20.0-debian-trixie-amd64.tar.xz
```

`.github/workflows/release.yml` builds each one inside `debian:trixie`,
unpacks it in a clean directory to run the tool, publishes the release, and
commits the resulting `sha256` back into `matrix.yml`.

## Supported tools

| tool | source |
|---|---|
| `node` | nodejs.org dist tarball (static linux-x64) |
| `python` | astral-sh/python-build-standalone (`install_only`) |
| `go` | go.dev/dl official tarball |
| `java` | Adoptium Temurin JDK |

Anything else is rejected by `install.sh` and by the Dockerfile-independent
build scripts: the set is deliberately small and explicit.

## Adding a tool version

Edit `matrix.yml` (bump `version`, update `artifact`, clear `sha256`), commit.
The release workflow rebuilds that asset and re-pins the checksum. Bumping a
version is a deliberate act - a CI that silently upgrades runtimes is a CI that
breaks builds nobody touched.
