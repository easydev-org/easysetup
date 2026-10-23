# Using pip with these toolchains

`pip install` fails against the Python we ship, with:

```
error: externally-managed-environment

× This environment is externally managed
╰─> This command has been disabled as it tries to modify the immutable
    `/nix/store` filesystem.
```

That is expected, and it is the same rule Debian and Fedora adopted in PEP 668.
It is not a bug in this setup and there is no flag you should add to get past it.

## What is actually happening

Two separate facts combine:

1. **The interpreter lives in `/nix/store`, which is read-only.** Nothing can
   write into it. Every file there has a hash-derived path, and its permissions
   are `r-xr-xr-x`. `pip install` needs to write into
   `<python>/lib/python3.14/site-packages`, which is inside that tree.

2. **The interpreter ships an `EXTERNALLY-MANAGED` marker.** The install above
   found it at
   `/nix/store/xahxrjs...-python3-3.14.8/lib/python3.14/EXTERNALLY-MANAGED`,
   containing exactly the message you saw. `pip` reads that file before touching
   anything and refuses.

The marker exists so the error is a clear explanation rather than a confusing
`Permission denied` partway through an install. Without it you would get a
partial write and a stack trace instead.

## What to use instead: a venv

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

This is the supported path, and it works. Measured on the published artifacts:

```
$ python3 -m venv /tmp/v          -> exit 0
$ /tmp/v/bin/pip install requests -> exit 0
$ /tmp/v/bin/python -c 'import requests; print(requests.__version__)'
2.34.2
```

The venv is a real directory you own, so `pip` writes there without complaint,
and the interpreter inside it is a symlink to the read-only one - which is fine,
because nothing needs to write to the interpreter itself.

## `--user` does not help

```
$ pip install --user requests
error: externally-managed-environment
```

The marker is not about *where* you install, it is about the interpreter being
managed by something other than pip. `--user` is refused for the same reason.
`--break-system-packages` does get past the check, but it writes into
`/nix/store`, which fails on the read-only mount, or - if it somehow succeeded -
would corrupt a path whose name is its content hash.

## Two more options

**Declare dependencies instead of installing them.** This is what nix is for, and
it is why the option exists at all:

```bash
nix shell nixpkgs#python3Packages.requests nixpkgs#python3
```

or, for a repeatable project, a `shell.nix`/`flake.nix` listing
`python3.withPackages (ps: [ ps.requests ])`. The advantage over a venv is that
the whole set is one hash: the same environment tomorrow, byte for byte.

**`uv`** also works and is worth knowing if speed matters:

```bash
uv venv && uv pip install requests
```

It creates a venv like `python3 -m venv` does, so the same reasoning applies.

## If you are building a Docker image

Create the venv during the build and put it somewhere you control:

```dockerfile
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
RUN pip install -r requirements.txt
```

The layer holds only `/opt/venv`, and `/nix/store` stays untouched.

## The short version

| command | result |
|---|---|
| `pip install X` | refused - PEP 668 |
| `pip install --user X` | refused - the marker is not location-based |
| `pip install --break-system-packages X` | fails on the read-only store, and would be wrong anyway |
| `python3 -m venv .venv && .venv/bin/pip install X` | **works** |
| `nix shell nixpkgs#python3Packages.X` | **works**, and is reproducible |

Nothing here is specific to this project. Any Python that lives in `/nix/store`
behaves this way, including one installed by `nix profile install nixpkgs#python3`.
