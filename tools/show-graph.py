#!/usr/bin/env python3
"""Print a readable summary of one architecture's dependency graph.

    tools/show-graph.py            # amd64
    ARCH=arm64 tools/show-graph.py

A separate file rather than an inline heredoc: the same summary is printed inside
a `for arch in ...` loop in CI, and a heredoc nested in a loop inside a YAML block
scalar is a reliable way to produce a file that no longer parses.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402


def main():
    arch = os.environ.get("ARCH", "amd64")
    path = matrixlib2.closures_path(ROOT, arch)
    d = json.load(open(path))
    print("arch: %s   setups: %d   base: %d"
          % (arch, len(d["setups"]), len(d["base"])))
    print()
    print("== setups that can drop paths (own < closure) ==")
    for name, e in sorted(d["setups"].items()):
        kept, total = len(e["own"]), e["closure_size"]
        if kept < total:
            print("  %-26s %4d/%4d kept  deps=%s"
                  % (name, kept, total, ", ".join(e["deps"]) or "-"))


if __name__ == "__main__":
    main()
