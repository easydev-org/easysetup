# easysetup

Prebuilt toolchain images for easydev CI. One image = one fixed set of runtimes,
so a CI job gets node / python / go / java **without installing anything at run
time**.

```
ghcr.io/easydev-org/easysetup:node22
ghcr.io/easydev-org/easysetup:node22-python312
ghcr.io/easydev-org/easysetup:all
```

## How a CI job uses it

```yaml
# .easy-platform/ci.yml
version: 1
on: [rr_opened, rr_synced]
jobs:
  test:
    setup: [node22, python312]     # resolved to the image above
    commands:
      - . /opt/setup/env.sh
      - node --version && python3 --version
      - npm ci && pytest
```

The job does not name a version and does not download anything: `setup:` is
matched against `matrix.yml`, and the matching image already contains the
toolchains.

## Layout inside the image

```
/opt/setup/node/bin/node
/opt/setup/python/bin/python3
/opt/setup/go/bin/go
/opt/setup/java/bin/java
/opt/setup/env.sh          -> prepends the ones that exist to PATH, sets JAVA_HOME
```

Nothing is installed into `/usr`. The base image's apt layer only carries shared
runtime libraries (`ca-certificates`, `libstdc++6`, `zlib1g`, `libssl3`, a C
toolchain for native modules) - never node/python/java/go themselves, so the
version is exactly what `matrix.yml` pins.

## matrix.yml is the authority

Both the build and the consumers read the same file:

- `.github/workflows/build.yml` builds exactly the `images:` listed.
- The platform's CI resolves `setup: [...]` against the same list and **fails
  loudly** for a combination that is not published.

Versions are pinned by hand. Reproducibility beats novelty: a CI that silently
picks up a new runtime breaks builds for reasons the author never changed.
`.github/workflows/refresh.yml` runs weekly and opens a **pull request** when a
pin is stale - it never pushes to main.

## Building locally

```bash
python3 -m pip install pyyaml
./build.sh                      # build every image in matrix.yml
./build.sh with ONLY=node22     # one image
PUSH=1 ./build.sh               # build + push to ghcr (needs docker login)
```

Each image is smoke-tested after the build: every tool it declares must answer
`--version` from a shell that only sourced `/opt/setup/env.sh`.

## Adding a combination

Append to `matrix.yml`:

```yaml
  - tag: go127-java21
    tools:
      go: "1.27.2"
      java: "21.0.8+9"
```

Commit; the workflow builds and publishes `:go127-java21`. No code change.

## Supported tools

| tool | source | notes |
|---|---|---|
| `node` | nodejs.org dist tarball | static Linux x64 build |
| `python` | astral-sh/python-build-standalone | self-contained CPython, no compile |
| `go` | go.dev/dl | official tarball |
| `java` | Adoptium Temurin | JDK; `JAVA_HOME` is exported |

Anything else is rejected by the Dockerfile (`unknown tool`) - the set is
deliberately small and explicit.
