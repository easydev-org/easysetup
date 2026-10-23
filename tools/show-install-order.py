#!/usr/bin/env python3
"""Print the install order install.sh will use, for the setups we are testing.

install.sh resolves a name to a directory, then walks closures.json to install
dependencies first. Running the same walk here shows what the CI assertions
should expect - without it the expected counts in install-test.yml would be
guesses.

    tools/show-install-order.py [setup ...]
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def order(setups, name, acc=None):
    acc = acc if acc is not None else []
    if name in acc:
        return acc
    for dep in setups.get(name, {}).get("deps", []):
        order(setups, dep, acc)
    if name not in acc:
        acc.append(name)
    return acc


def main(argv):
    doc = json.load(open(os.path.join(ROOT, "closures.json")))
    setups = doc["setups"]
    names = argv[1:] or ["composer-2.10.3", "cargo-1.99.0",
                         "pip-26.1.2", "jq-1.8.2"]
    for n in names:
        if n not in setups:
            print("%-20s MISSING from closures.json" % n)
            continue
        o = order(setups, n)
        print("%-20s -> %s   (%d setup(s))" % (n, " ".join(o), len(o)))


if __name__ == "__main__":
    main(sys.argv)
