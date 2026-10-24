#!/usr/bin/env python3
"""Print every setup with its dependency list, one per line.

The dependency graph is what closures.json records, and it was derived from the
nix closures by compute-deps.py - so this prints what the installer actually
acts on, not a copy that could drift.

Two forms:

    tools/list-deps.py                 package + its direct dependencies
    tools/list-deps.py --transitive    package + everything it pulls in

`base` is a dependency of almost everything (it is the shared glibc set), so it
is shown as `base` rather than repeated per line.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main(argv):
    transitive = "--transitive" in argv
    doc = json.load(open(matrixlib2.closures_path(ROOT)))
    setups = doc["setups"]
    base = set(doc.get("base", []))

    def closure_deps(name, seen=None):
        """Everything name needs, transitively, excluding the shared base."""
        seen = seen if seen is not None else []
        for d in setups.get(name, {}).get("deps", []):
            if d in seen:
                continue
            seen.append(d)
            closure_deps(d, seen)
        return seen

    width = max(len(n) for n in setups)
    print("%-*s | %-9s | %-9s | %s"
          % (width, "SETUP", "OWN", "CLOSURE", "DEPENDS ON"))
    print("%s-+-%s-+-%s-+-%s" % ("-" * width, "-" * 9, "-" * 9, "-" * 40))

    for name in sorted(setups):
        e = setups[name]
        if transitive:
            deps = [d for d in closure_deps(name) if d != name]
        else:
            deps = e.get("deps", [])
        dep_s = ", ".join(deps) if deps else "-"
        print("%-*s | %9d | %9d | %s"
              % (width, name, len(e["own"]), e["closure_size"], dep_s))

    print()
    print("total: %d setups, %d shared base paths" % (len(setups), len(base)))


if __name__ == "__main__":
    main(sys.argv)
