#!/usr/bin/env python3
"""test_resolve.py — how a setup name is resolved.

The rule being pinned down: a name may be a PREFIX of the version, matched by
dot-separated segment, and several entries matching means "the newest of those".

    node-22          -> node-22.23.4      (only 22.x present)
    node-22.23       -> node-22.23.4
    node-22.23.4     -> node-22.23.4      (exact)
    node-2           -> error             ("2" is not a segment of "22")
    node-99          -> error
    rust-1.99.1      -> the HOST entry, never a cross target
"""

import pathlib
import sys

sys.path.insert(0, "/tmp/es")
import matrixlib  # noqa: E402

MATRIX = pathlib.Path("/tmp/_resolve.yml")
MATRIX.write_text("""\
base:
  distro: debian-trixie

setups:
  - tool: node
    version: "22.23.4"
    artifact: node-22.23.4.tar.xz
    sha256: ""
  - tool: node
    version: "22.24.0"
    artifact: node-22.24.0.tar.xz
    sha256: ""
  - tool: node
    version: "24.22.1"
    artifact: node-24.22.1.tar.xz
    sha256: ""
  - tool: java
    version: "21.0.12+101"
    artifact: java-21.0.12-101.tar.xz
    sha256: ""
  - tool: rust
    version: "1.99.1"
    artifact: rust-1.99.1.tar.xz
    sha256: ""
  - tool: rust
    version: "1.99.1"
    target: x86_64-pc-windows-gnu
    artifact: rust-1.99.1-gnu.tar.xz
    sha256: ""
  - tool: python
    version: "3.12.15"
    artifact: python-3.12.15.tar.xz
    sha256: ""
  - tool: python
    version: "3.15.1"
    artifact: python-3.15.1.tar.xz
    sha256: ""
""")

fail = 0


def ok(name, got, want):
    global fail
    if got == want:
        print(f"ok   {name} -> {got}")
    else:
        print(f"FAIL {name}: got {got!r}, want {want!r}")
        fail = 1


def err(name):
    global fail
    try:
        r = matrixlib.resolve(name, str(MATRIX))
    except matrixlib.Ambiguous as e:
        print(f"FAIL {name}: ambiguous ({e})")
        fail = 1
        return
    if r is None:
        print(f"ok   {name} -> no match")
    else:
        print(f"FAIL {name}: matched {r['dir']}, expected no match")
        fail = 1


ok("node-22", matrixlib.resolve("node-22", str(MATRIX))["dir"], "node-22.24.0")
ok("node-22.23", matrixlib.resolve("node-22.23", str(MATRIX))["dir"], "node-22.23.4")
ok("node-22.23.4", matrixlib.resolve("node-22.23.4", str(MATRIX))["dir"], "node-22.23.4")
ok("node-24", matrixlib.resolve("node-24", str(MATRIX))["dir"], "node-24.22.1")
ok("java-21", matrixlib.resolve("java-21", str(MATRIX))["dir"], "java-21.0.12+101")
ok("java-21.0.12", matrixlib.resolve("java-21.0.12", str(MATRIX))["dir"], "java-21.0.12+101")

# A bare rust version must pick the HOST build, not a cross target.
ok("rust-1.99.1 picks host",
   matrixlib.resolve("rust-1.99.1", str(MATRIX))["dir"], "rust-1.99.1")
ok("rust cross is still exact",
   matrixlib.resolve("rust-1.99.1+x86_64-pc-windows-gnu", str(MATRIX))["dir"],
   "rust-1.99.1+x86_64-pc-windows-gnu")

# "2" must not be treated as a prefix of "22" — segments, not strings.
err("node-2")
err("node-99")
err("nope-1")

# A whole-major prefix IS valid: `python-3` means the newest 3.x.
ok("python-3 -> newest 3.x",
   matrixlib.resolve("python-3", str(MATRIX))["dir"], "python-3.15.1")
ok("python-3.12", matrixlib.resolve("python-3.12", str(MATRIX))["dir"], "python-3.12.15")

print(f"\ntest_resolve: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
