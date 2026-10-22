"""matrixlib.py — the single parser for matrix.yml.

Every consumer (install.sh, bump.py, the release workflow, selftest) needs the
same answers to the same questions, so the shape is defined ONCE, here:

  setups are a LIST of entries; `version` is a field, never part of a name;
  the install directory and the release tag are DERIVED as <tool>-<version>.

`install.sh` shells out to this file:

    python3 matrixlib.py list                  # "<tool>-<version>" per line
    python3 matrixlib.py get <dir> <field>     # one field of one entry
    python3 matrixlib.py apt <dir>             # apt_deps, space separated

DELIBERATELY DEPENDENCY-FREE: it uses only the standard library, not PyYAML.
The release job runs inside `debian:trixie` where PyYAML is not installed, and
`pip install pyyaml` there would break the rule that a build needs nothing
beyond apt - so the manifest is parsed by a small parser that understands the
exact subset this file uses (a top-level mapping plus a list of flat mappings).
That subset is checked at load time; anything outside it raises instead of
being silently misread.
"""

import sys

MATRIX = "matrix.yml"


def _scalar(s):
    """Turn one YAML scalar into a Python value."""
    s = s.strip()
    if not s:
        return ""
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        return [] if not inner else [x.strip().strip('"').strip("'")
                                     for x in inner.split(",")]
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def load(path=MATRIX):
    """Parse matrix.yml into a list of entries, each with `dir` and `tag`."""
    entries = []
    cur = None
    in_setups = False

    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        # Strip comments that are not inside a quoted value. The manifest only
        # uses `#` for whole-line comments plus one trailing case, so a simple
        # rule is enough - but be explicit about it.
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.endswith("#"):
            stripped = stripped[:-1].rstrip()

        indent = len(line) - len(line.lstrip())

        if indent == 0:
            in_setups = stripped == "setups:"
            cur = None
            continue
        if not in_setups:
            continue

        # `  - tool: node` starts a new entry (2 spaces + "- ")
        if indent == 2 and stripped.startswith("- "):
            cur = {}
            entries.append(cur)
            rest = stripped[2:]
            k, _, v = rest.partition(":")
            cur[k.strip()] = _scalar(v)
            continue

        # `    key: value` belongs to the current entry (4 spaces)
        if indent == 4 and cur is not None:
            k, _, v = stripped.partition(":")
            cur[k.strip()] = _scalar(v)
            continue

        raise ValueError(f"matrixlib: unsupported line in matrix.yml: {raw!r}")

    if not entries:
        raise ValueError("matrixlib: no setups found in matrix.yml")

    for e in entries:
        if "tool" not in e or "version" not in e:
            raise ValueError(f"matrixlib: entry without tool/version: {e}")
        # "rust-1.99.1+x86_64-pc-windows-gnu": two entries can share tool +
        # version and differ only by target (host toolchain vs cross std), so
        # the target is part of the identity.
        base = f'{e["tool"]}-{e["version"]}'
        if e.get("target"):
            base += f'+{e["target"]}'
        e["dir"] = base
        e["tag"] = base
    return entries


def by_dir(d, path=MATRIX):
    for e in load(path):
        if e["dir"] == d:
            return e
    return None


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd = argv[1]

    try:
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
            print(" ".join(v) if isinstance(v, list) else ("" if v is None else v))
            return 0

        if cmd == "apt":
            e = by_dir(argv[2])
            if e is None:
                sys.exit(f"matrixlib: no setup '{argv[2]}'")
            v = e.get("apt_deps") or []
            print(" ".join(v) if isinstance(v, list) else v)
            return 0
    except (ValueError, OSError) as e:
        sys.exit(f"matrixlib: {e}")

    sys.exit(f"matrixlib: unknown command '{cmd}'")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
