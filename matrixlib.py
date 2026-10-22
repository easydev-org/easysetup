"""matrixlib.py — the single parser for matrix.yml.

Every consumer (install.sh, bump.py, the release workflow, selftest) needs the
same answers to the same questions, so the shape is defined ONCE, here:

  setups are a LIST of entries; `version` is a field, never part of a name;
  the install directory and the release tag are DERIVED as <tool>-<version>.

`install.sh` cannot import Python, so it shells out to this file:

    python3 matrixlib.py list                  # "<tool>-<version>" per line
    python3 matrixlib.py get <dir> <field>     # one field of one entry
    python3 matrixlib.py apt <dir>             # apt_deps, space separated

That keeps ONE implementation of the format instead of an awk copy that drifts
from the Python one (which is exactly how the two got out of sync before).
"""

import sys

import yaml

MATRIX = "matrix.yml"


def load(path=MATRIX):
    """Return the setups as a list of dicts, each with `dir` and `tag` added."""
    doc = yaml.safe_load(open(path))
    out = []
    for e in doc["setups"]:
        e = dict(e)
        # "rust-1.99.1+x86_64-pc-windows-gnu" keeps the target in the name: two
        # entries can share tool+version and differ only by target (rust host vs
        # rust cross-compiler), so the target is part of the identity.
        base = f'{e["tool"]}-{e["version"]}'
        if e.get("target"):
            base += f'+{e["target"]}'
        e["dir"] = base
        e["tag"] = base
        out.append(e)
    return out


def by_dir(d, path=MATRIX):
    for e in load(path):
        if e["dir"] == d:
            return e
    return None


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd = argv[1]

    if cmd == "list":
        for e in load():
            print(e["dir"])
        return 0

    if cmd == "get":
        if len(argv) < 4:
            sys.exit("matrixlib: get <dir> <field>")
        e = by_dir(argv[2])
        if e is None:
            sys.exit(f"matrixlib: no setup '{argv[2]}'")
        v = e.get(argv[3], "")
        print("" if v is None else v)
        return 0

    if cmd == "apt":
        e = by_dir(argv[2])
        if e is None:
            sys.exit(f"matrixlib: no setup '{argv[2]}'")
        print(" ".join(e.get("apt_deps") or []))
        return 0

    if cmd == "dump":                       # every field, tab separated
        for e in load():
            print("\t".join([e["dir"], e.get("tool", ""), e.get("version", ""),
                             e.get("target", ""), e.get("artifact", ""),
                             e.get("sha256", "") or ""]))
        return 0

    sys.exit(f"matrixlib: unknown command '{cmd}'")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
