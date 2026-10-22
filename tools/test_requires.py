#!/usr/bin/env python3
"""How a `requires` entry is interpreted.

The problem this solves: `requires: [erlang-29.1.2]` hard-codes a version into
every dependent entry. When elixir 1.21 needs erlang 30, whoever adds that entry
has to remember to change the dependency too - and if they forget, the install
succeeds with the wrong runtime.

So a requirement may carry a RANGE, and the range is resolved against the
versions we actually publish:

    erlang-29.1.2        exactly that setup
    erlang-29            that tool, newest 29.x
    erlang>=29 <30       any 29.x (comparison on the version)
    erlang>=29,<30       same, comma-separated
    erlang               newest of that tool

Everything is resolved against the manifest, so a range that matches nothing is
an error rather than a silent no-op.
"""

import pathlib
import sys

sys.path.insert(0, "/tmp/es")
import matrixlib  # noqa: E402

MATRIX = pathlib.Path("/tmp/_requires.yml")
MATRIX.write_text('''\
setups:
  - tool: erlang
    version: "29.1.2"
  - tool: erlang
    version: "29.0.1"
  - tool: erlang
    version: "30.0.0"
  - tool: elixir
    version: "1.20.4"
    requires: [erlang@>=29 <30]
  - tool: elixir
    version: "1.21.0"
    requires: [erlang@>=30]
  - tool: lua
    version: "5.4.8"
  - tool: luarocks
    version: "3.12.2"
    requires: [lua]
  - tool: badrange
    version: "1.0"
    requires: [erlang@>=99]
  - tool: unknownreq
    version: "1.0"
    requires: [nosuchtool]
  - tool: rust
    version: "1.99.1"
  - tool: rust-toolchain-x86_64-pc-windows-gnu
    version: "1.99.1"
    requires: [rust-1.99.1]
''')

fail = 0


def check(name, got, want):
    global fail
    print(("ok   " if got == want else "FAIL ") + name + f" -> {got}")
    if got != want:
        print(f"     want {want!r}")
        fail = 1


def chain_of(name):
    return [e["dir"] for e in matrixlib.resolve_chain(name, str(MATRIX))]


# A range picks the NEWEST version that satisfies it, not the first found.
check("range >=29 <30 picks 29.1.2",
      chain_of("elixir-1.20.4"), ["erlang-29.1.2", "elixir-1.20.4"])

# A different range on the same tool picks a different version.
check("range >=30 picks 30.0.0",
      chain_of("elixir-1.21.0"), ["erlang-30.0.0", "elixir-1.21.0"])

# A bare tool name means "newest of that tool".
check("bare tool picks newest", chain_of("luarocks-3.12.2"),
      ["lua-5.4.8", "luarocks-3.12.2"])

# An exact setup still works, unchanged from before.
check("exact requirement still works",
      chain_of("rust-toolchain-x86_64-pc-windows-gnu-1.99.1"),
      ["rust-1.99.1", "rust-toolchain-x86_64-pc-windows-gnu-1.99.1"])

# A range matching nothing must be an ERROR, not a silent skip: otherwise the
# dependent installs with no runtime at all and fails much later.
for bad, why in (("badrange-1.0", "range matches nothing"),
                 ("unknownreq-1.0", "unknown tool")):
    try:
        matrixlib.resolve_chain(bad, str(MATRIX))
        print(f"FAIL {why} was not reported")
        fail = 1
    except ValueError as e:
        print(f"ok   {why} reported ({str(e)[:52]})")

print(f"\ntest_requires: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
