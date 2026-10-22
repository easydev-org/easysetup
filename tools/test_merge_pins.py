#!/usr/bin/env python3
"""The matrix.yml pin merge must keep valid pins and drop stale ones.

This exists because the pins were erased once: the local matrix.yml has empty
sha256 (CI owns that column) and a verbatim upload wiped all 42, which made
install.sh refuse to unpack anything.
"""

import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location(
    "merge_pins", str(pathlib.Path(__file__).with_name("merge-pins.py")))
mp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp)

LOCAL = '''\
setups:
  - tool: node
    version: "22.23.4"
    artifact: node-22.23.4.tar.xz
    sha256: ""
  - tool: r
    version: "4.6.1"
    artifact: r-4.6.1.tar.xz
    sha256: ""
  - tool: rust-toolchain-x86_64-pc-windows-gnu
    version: "1.99.1"
    artifact: rust-toolchain-x86_64-pc-windows-gnu-1.99.1.tar.xz
    sha256: ""
'''

REMOTE = '''\
setups:
  - tool: node
    version: "22.23.4"
    artifact: node-22.23.4.tar.xz
    sha256: "aaaa1111"
  - tool: r
    version: "4.6.1"
    artifact: r-4.6.1-OLD.tar.xz
    sha256: "bbbb2222"
  - tool: rust-toolchain-x86_64-pc-windows-gnu
    version: "1.99.1"
    artifact: rust-toolchain-x86_64-pc-windows-gnu-1.99.1.tar.xz
    sha256: "cccc3333"
'''

fail = 0


def check(name, cond):
    global fail
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fail = 1


merged, filled = mp.merge_pins(LOCAL, REMOTE)
check("node pin carried over", 'sha256: "aaaa1111"' in merged)
check("rust pin carried over", 'sha256: "cccc3333"' in merged)
check("stale pin dropped when the artifact name changed", "bbbb2222" not in merged)
check("count reported", filled == 2)
# An entry the remote does not know must stay unpinned (never invent a pin).
LOCAL2 = LOCAL + ('  - tool: newtool\n'
                  '    version: "1.0"\n'
                  '    artifact: newtool-1.0.tar.xz\n'
                  '    sha256: ""\n')
# Two entries stay empty: `newtool` (unknown to the remote) and `r` (its
# artifact name changed, so the old pin is stale and must not be reused).
merged2, filled2 = mp.merge_pins(LOCAL2, REMOTE)
check("unknown and stale entries stay unpinned", merged2.count('sha256: ""') == 2)
check("still only the two known pins were filled", filled2 == 2)

print(f"\ntest_merge_pins: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
