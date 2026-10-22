#!/usr/bin/env python3
"""The matrix.yml pin merge must keep valid pins and drop stale ones.

This exists because the pins were erased once: the local matrix.yml has empty
sha256 (CI owns that column), and a verbatim upload wiped all 42 of them, which
made install.sh refuse to unpack anything.
"""

import importlib.util
import sys

spec = importlib.util.spec_from_file_location("push", "/tmp/es/push.py")
push = importlib.util.module_from_spec(spec)
sys.argv = ["push.py"]
# Importing push.py runs the upload loop; give it nothing to do.
import pathlib
pathlib.Path("/tmp/_empty_root").mkdir(exist_ok=True)
push.ROOT = pathlib.Path("/tmp/_empty_root")
spec.loader.exec_module(push)

LOCAL = """\
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
"""

REMOTE = """\
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
"""

merged, filled = push.merge_pins(LOCAL, REMOTE)

fail = 0


def check(name, cond):
    global fail
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fail = 1


check("node pin carried over", 'sha256: "aaaa1111"' in merged)
check("rust pin carried over", 'sha256: "cccc3333"' in merged)
# r's artifact NAME changed, so its old pin must NOT be copied - the bytes are
# different and the pin would be a lie.
check("stale pin dropped when artifact changed", 'bbbb2222' not in merged)
check("count reported", filled == 2)

# A pin must never be invented for an entry the remote does not know.
LOCAL2 = LOCAL + """\
  - tool: newtool
    version: "1.0"
    artifact: newtool-1.0.tar.xz
    sha256: ""
"""
merged2, filled2 = push.merge_pins(LOCAL2, REMOTE)
check("unknown entry stays unpinned", merged2.count('sha256: ""') == 1)
check("still only two pins filled", filled2 == 2)

print(f"\ntest_merge_pins: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
