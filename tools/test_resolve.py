#!/usr/bin/env python3
"""test_resolve.py — name resolution and dependency resolution.

Two separate rules, tested separately:

  * a setup name may abbreviate the VERSION (`node-22`), by dot-segment prefix;
  * a setup may `requires` another, and installing it installs the dependency
    first, once.

Cross-compile toolchains used to be `+components`; they are now ordinary setups
whose name carries the target (`rust-toolchain-x86_64-pc-windows-gnu-1.99.1`),
so a tool name containing dashes must still resolve.
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
  - tool: node
    version: "22.24.0"
  - tool: node
    version: "24.22.1"
  - tool: java
    version: "21.0.12+101"
  - tool: rust
    version: "1.99.1"
  - tool: rust-toolchain-x86_64-pc-windows-gnu
    builder: rust
    version: "1.99.1"
    requires: [rust-1.99.1]
  - tool: erlang
    version: "29.1.2"
  - tool: elixir
    version: "1.20.4"
    requires: [erlang-29.1.2]
  - tool: lua
    version: "5.4.8"
  - tool: luarocks
    version: "3.12.2"
    requires: [lua-5.4.8]
  - tool: cyclic
    version: "1.0"
    requires: [cyclic2-1.0]
  - tool: cyclic2
    version: "1.0"
    requires: [cyclic-1.0]
""")

fail = 0


def ok(name, got, want):
    global fail
    print(("ok   " if got == want else "FAIL ") + name + f" -> {got}")
    if got != want:
        print(f"     want {want!r}")
        fail = 1


def none(name):
    global fail
    r = matrixlib.resolve(name, str(MATRIX))
    print(("ok   " if r is None else "FAIL ") + name + " -> " +
          ("no match" if r is None else r["dir"]))
    if r is not None:
        fail = 1


# --- version prefixes ------------------------------------------------------
ok("node-22", matrixlib.resolve("node-22", str(MATRIX))["dir"], "node-22.24.0")
ok("node-22.23", matrixlib.resolve("node-22.23", str(MATRIX))["dir"], "node-22.23.4")
ok("node-22.23.4", matrixlib.resolve("node-22.23.4", str(MATRIX))["dir"], "node-22.23.4")
ok("java-21", matrixlib.resolve("java-21", str(MATRIX))["dir"], "java-21.0.12+101")

# segments, not characters
none("node-2")
none("node-99")

# --- a tool name may contain dashes ---------------------------------------
ok("long tool name, version prefix",
   matrixlib.resolve("rust-toolchain-x86_64-pc-windows-gnu-1.99", str(MATRIX))["dir"],
   "rust-toolchain-x86_64-pc-windows-gnu-1.99.1")
ok("long tool name, bare major",
   matrixlib.resolve("rust-toolchain-x86_64-pc-windows-gnu-1", str(MATRIX))["dir"],
   "rust-toolchain-x86_64-pc-windows-gnu-1.99.1")

# --- requires is followed, dependency first, once -------------------------
chain = [e["dir"] for e in matrixlib.resolve_chain("elixir-1", str(MATRIX))]
ok("elixir pulls erlang first", chain, ["erlang-29.1.2", "elixir-1.20.4"])

chain = [e["dir"] for e in matrixlib.resolve_chain("luarocks-3", str(MATRIX))]
ok("luarocks pulls lua first", chain, ["lua-5.4.8", "luarocks-3.12.2"])

chain = [e["dir"] for e in matrixlib.resolve_chain(
    "rust-toolchain-x86_64-pc-windows-gnu-1", str(MATRIX))]
ok("cross toolchain pulls host rust",
   chain, ["rust-1.99.1", "rust-toolchain-x86_64-pc-windows-gnu-1.99.1"])

# A setup with no requires is just itself.
chain = [e["dir"] for e in matrixlib.resolve_chain("node-22", str(MATRIX))]
ok("node has no dependency", chain, ["node-22.24.0"])

# --- a cycle must be refused, not looped ----------------------------------
try:
    matrixlib.resolve_chain("cyclic-1", str(MATRIX))
    print("FAIL cycle not detected")
    fail = 1
except ValueError as e:
    print(f"ok   cycle refused ({e})")

print(f"\ntest_resolve: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
