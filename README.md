# easysetup

Prebuilt toolchains for CI, shipped as portable tarballs.

```yaml
- uses: easydev-org/easysetup@main
  with:
    tools: node python swift
```

## What a setup is

One nixpkgs attribute, declared as one file:

```nix
# setups/swift.nix
{ pkgs }:
pkgs.swift
```

The build is `nix build`, then the closure is exported and packed. There is no
per-tool script, no apt list and no dependency resolution of our own, because
nix computes the closure and cache.nixos.org already has it built:

```
$ nix build --dry-run .#swift
these 90 paths will be fetched (1470.23 MiB download, 5843.57 MiB unpacked)
paths built locally: 0
```

## What installing costs

One download and one unpack:

```
curl the tarball  ->  verify sha256  ->  tar -xJf -C /
```

Nothing is compiled at install time, and **nix is not needed to run the result**.
A chroot containing only the unpacked tarball runs the tool - no `/usr`, no
shell, no nix. That is the property the whole design rests on.

## Where things land

```
/nix/store/<hash>-<name>/        the tree, exactly as nix built it
/nix/setup-root-<tool>-<ver>     one line: "<store-path>|<bin dirs>"
/opt/setup/env.sh                puts every tool on PATH
```

The store path is kept verbatim because every binary in the closure has it baked
in as the ELF interpreter and rpath. Moving the tree to `/opt/setup` is possible
- it was tested with `patchelf --force-rpath` - but it means rewriting every
binary and every `.la`/`.pc` file, and it discards nix's integrity check.

Two setups can each ship a different build of the same library without
interfering: the hash is the isolation. `libssl` from one closure and `libssl`
from another are different paths, so neither can shadow the other.

## Requirements

The action needs `debian:trixie-slim` (or anything with glibc >= 2.41):

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container: debian:trixie-slim
```

Ubuntu 24.04 has glibc 2.39 and cannot load the artifacts; the action detects
that and says so instead of installing something that will not start.

The four bootstrap packages (`curl`, `xz-utils`, `python3`, `ca-certificates`)
are installed by the action. They are the only apt call; after that every setup
is pure download.

## Adding a setup

```nix
# setups/kotlin.nix
{ pkgs }:
pkgs.kotlin
```

then add it to `matrix-nix.yml` so it has a friendly name:

```yaml
  - tool: kotlin
    attr: nixpkgs#kotlin
    version: "2.2.0"
```

`tools/gen-setups.py` writes the `.nix` files from the manifest, so in practice
only the manifest changes. Give a setup a hand-written `.nix` when it needs an
override; the generator leaves those alone.

## Building a release

`.github/workflows/nix-release.yml`, manually:

```
only: swift        # one setup
only: ""           # all of them
```

Each setup becomes one release tagged `<tool>-<version>`, holding the tarball and
its `.sha256`. The checksum is computed from the file being uploaded, so it
cannot describe a tarball that was never published.

## Layout

```
setups/*.nix           one expression per setup
matrix-nix.yml         names, attributes, versions
matrixlib2.py          the manifest parser (stdlib only)
flake.nix              one nixpkgs pin for every setup
install.sh             resolve, download, verify, unpack
tools/build-nixpkg.sh  nix build -> export closure -> tarball
tools/gen-env.sh       write env.sh from /nix/setup-root-*
tools/gen-setups.py    manifest -> setups/*.nix
action.yml             the composite action
