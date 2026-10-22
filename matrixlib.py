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
    list_key = None          # the key whose block list we are currently inside

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
            list_key = None
            continue
        if not in_setups:
            continue

        # `  - tool: node` starts a new entry (2 spaces + "- ")
        if indent == 2 and stripped.startswith("- "):
            cur = {}
            entries.append(cur)
            list_key = None
            rest = stripped[2:]
            k, _, v = rest.partition(":")
            cur[k.strip()] = _scalar(v)
            continue

        # `    key: value` belongs to the current entry (4 spaces)
        if indent == 4 and cur is not None:
            k, _, v = stripped.partition(":")
            k = k.strip()
            if v.strip() == "":
                # `components:` with a block list of `      - item` lines.
                cur[k] = []
                list_key = k
            else:
                cur[k] = _scalar(v)
                list_key = None
            continue

        # `      - item` continues the block list opened at indent 4.
        if indent == 6 and stripped.startswith("- ") and cur is not None and list_key:
            cur[list_key].append(_scalar(stripped[2:]))
            continue

        raise ValueError(f"matrixlib: unsupported line in matrix.yml: {raw!r}")

    if not entries:
        raise ValueError("matrixlib: no setups found in matrix.yml")

    for e in entries:
        if "tool" not in e or "version" not in e:
            raise ValueError(f"matrixlib: entry without tool/version: {e}")
        # `components` is the general mechanism for "optional add-ons installed
        # alongside a tool". Today the only user is rust, where a cross-compile
        # std is a component of the toolchain:
        #
        #   tool: rust, version: 1.99.1,
        #   components: [x86_64-pc-windows-gnu]
        #
        # The directory (and release tag) carries them as `+<c1>+<c2>`, so two
        # entries sharing tool+version stay distinguishable:
        #
        #   rust-1.99.1
        #   rust-1.99.1+x86_64-pc-windows-gnu
        #
        # `target` is accepted as the old single-value spelling; it is folded
        # into `components` here so nothing downstream has to know both names.
        comps = e.get("components")
        if comps is None:
            comps = []
        elif isinstance(comps, str):
            comps = [comps]
        if e.get("target"):
            comps = list(comps) + [e["target"]]
            del e["target"]
        e["components"] = list(comps)

        base = f'{e["tool"]}-{e["version"]}'
        for c in e["components"]:
            base += f'+{c}'
        e["dir"] = base
        e["tag"] = base
    return entries


def by_dir(d, path=MATRIX):
    for e in load(path):
        if e["dir"] == d:
            return e
    return None


class Ambiguous(Exception):
    """A name matched more than one entry and no rule picked a winner."""


def _vkey(version):
    """Numeric sort key for a version string ("22.23.4", "21.0.12+101")."""
    main, _, build = version.partition("+")
    nums = [int(x) for x in __import__("re").findall(r"\d+", main)]
    bnum = [int(x) for x in __import__("re").findall(r"\d+", build)]
    return (nums, bnum)


def resolve(name, path=MATRIX):
    """Resolve a setup name to one entry.

    Two independent things may be abbreviated, and they use different syntax:

    VERSION is a dot-separated PREFIX, because people write `node-22`:

        node-22       -> node-22.23.4     (the newest 22.x we publish)
        node-22.23    -> node-22.23.4
        node-22.23.4  -> node-22.23.4     (exact always wins)

    A COMPONENT is named after the version with `@`, and only its FULL name is
    accepted - no partial matching:

        rust-1.99.1@x86_64-pc-windows-gnu  -> that entry
        rust-1.99.1@windows-gnu            -> no match (not a full component name)

    Version matching is by whole segments, not characters: `node-2` does NOT
    match `node-22.23.4`, because "2" is not a segment of "22". A character
    prefix would silently install the wrong major version.

    With no `@`, only entries WITHOUT components are considered, so a bare
    `rust-1.99.1` is always the host toolchain and never a cross-compile one.

    Returns None when nothing matches. Raises Ambiguous if two entries match
    equally, which the manifest should never contain.
    """
    entries = load(path)

    # 1) Exact directory match always wins (this is how `+component` names and
    #    fully spelled versions land).
    for e in entries:
        if e["dir"] == name:
            return e

    # 2) `tool-<version prefix>@<component>`
    base, sep, comp = name.partition("@")
    if sep:
        want_comps = [comp]
    else:
        want_comps = []

    tool, _, want = base.partition("-")
    if not tool or not want:
        return None
    want_segments = want.split(".")

    matches = []
    for e in entries:
        if e["tool"] != tool:
            continue
        # The component set must match EXACTLY: a bare name selects only
        # component-free entries; `@x` selects only entries whose components are
        # exactly ["x"].
        if sorted(e["components"]) != sorted(want_comps):
            continue
        have_segments = e["version"].split("+")[0].split(".")
        if len(want_segments) > len(have_segments):
            continue
        if have_segments[:len(want_segments)] != want_segments:
            continue
        matches.append(e)

    if not matches:
        return None
    if len(matches) == 1:
        return matches[0]

    # Several entries on the same line: newest wins. That is what "node-22"
    # means when we publish 22.23.4 and 22.24.0 - you asked for the 22 line,
    # so give you the newest of it.
    matches.sort(key=lambda e: _vkey(e["version"]), reverse=True)
    newest = matches[0]
    if _vkey(matches[1]["version"]) == _vkey(newest["version"]):
        raise Ambiguous(
            f"{name!r} matches {newest['dir']} and {matches[1]['dir']} equally")
    return newest


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
            e = resolve(argv[2])
            if e is None:
                sys.exit(f"matrixlib: no setup '{argv[2]}'")
            v = e.get(argv[3], "")
            print(" ".join(v) if isinstance(v, list) else ("" if v is None else v))
            return 0

        if cmd == "apt":
            e = resolve(argv[2])
            if e is None:
                sys.exit(f"matrixlib: no setup '{argv[2]}'")
            v = e.get("apt_deps") or []
            print(" ".join(v) if isinstance(v, list) else v)
            return 0

        if cmd == "resolve":
            # Print the concrete directory a name resolves to, and why when it
            # cannot: this is what makes `install.sh node-22` self-explanatory.
            e = resolve(argv[2])
            if e is None:
                avail = ", ".join(x["dir"] for x in load())
                sys.exit(f"matrixlib: no setup matches '{argv[2]}'\n"
                         f"  available: {avail}")
            print(e["dir"])
            return 0
    except (ValueError, OSError) as e:
        sys.exit(f"matrixlib: {e}")

    sys.exit(f"matrixlib: unknown command '{cmd}'")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
