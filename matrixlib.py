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
        # A setup is <tool>-<version>. Nothing else goes into the name: an
        # add-on that used to be a `+component` is now its own setup with its
        # own tool name (`rust-toolchain-x86_64-pc-windows-gnu`), and its
        # dependency on the host toolchain is declared with `requires`.
        e["dir"] = f'{e["tool"]}-{e["version"]}'
        e["tag"] = e["dir"]

        # `requires` lists setups that must be installed first. Each entry is
        # itself a resolvable name (`erlang-28.0.0`), so a version prefix works.
        reqs = e.get("requires") or []
        if isinstance(reqs, str):
            reqs = [reqs]
        e["requires"] = list(reqs)

        # `builder` names the script that produces the tarball, defaulting to
        # the tool name. It exists because several setups can share one build
        # script: rust-toolchain-* are all produced by build-rust.sh.
        e["builder"] = e.get("builder") or e["tool"]
    return entries


def by_dir(d, path=MATRIX):
    for e in load(path):
        if e["dir"] == d:
            return e
    return None


class Ambiguous(Exception):
    """A name matched more than one entry and no rule picked a winner."""


class _Seen:
    """Carries the two sets resolve_chain needs across recursive calls."""

    __slots__ = ("done", "active")

    def __init__(self, done, active):
        self.done = done
        self.active = active


def _cmp_ok(version, op, want):
    """Compare a version against `want` using a numeric, component-wise order."""
    a = _vkey(version)[0]
    b = _vkey(want)[0]
    # Pad so 29 < 29.1 and 29.1.0 == 29.1
    n = max(len(a), len(b))
    a = a + [0] * (n - len(a))
    b = b + [0] * (n - len(b))
    if op == ">=":
        return a >= b
    if op == ">":
        return a > b
    if op == "<=":
        return a <= b
    if op == "<":
        return a < b
    if op == "==":
        return a == b
    if op == "!=":
        return a != b
    raise ValueError(f"unknown operator {op!r}")


def _matches_range(version, spec):
    """Does `version` satisfy a range spec like '>=29 <30' or '>=29,<30'?"""
    for part in spec.replace(",", " ").split():
        m = __import__("re").match(r"^(>=|<=|==|!=|>|<)?\s*(\d[\w.]*)$", part)
        if not m:
            raise ValueError(f"cannot parse version constraint {part!r}")
        op = m.group(1) or "=="
        if not _cmp_ok(version, op, m.group(2)):
            return False
    return True


def resolve_requirement(req, path=MATRIX):
    """Resolve one `requires` entry to a concrete setup.

    Accepted forms, all resolved against what the manifest actually publishes:

        erlang-29.1.2     exactly that directory
        erlang-29         that tool, newest 29.x   (version prefix)
        erlang>=29 <30    any version in the range  (newest wins)
        erlang>=29,<30    same, comma-separated
        erlang            newest of that tool

    `@` separates a tool from a constraint (`erlang@>=29 <30`) so the two are
    unambiguous - without it, `erlang-29` and `erlang` would have to be told
    apart by guessing.

    Raises ValueError when nothing matches. A dependency that silently resolves
    to nothing would leave the dependent installed with no runtime, which fails
    much later and far from the cause.
    """
    text = req.strip()

    # Exact directory name wins (this is the old behaviour, still valid).
    for e in load(path):
        if e["dir"] == text:
            return e

    tool, sep, spec = text.partition("@")
    spec = spec.strip()
    if not sep:
        # No constraint. A bare `<tool>-<version-ish>` is still tried as a
        # prefix by `resolve`; otherwise treat the text as a tool name.
        e = resolve(text, path)
        if e is not None:
            return e

    candidates = [x for x in load(path) if x["tool"] == tool]
    if not candidates:
        raise ValueError(f"requires {text!r}: no setup has tool {tool!r}")

    if not spec:
        chosen = max(candidates, key=lambda x: _vkey(x["version"]))
        return chosen

    ok = [x for x in candidates if _matches_range(x["version"], spec)]
    if not ok:
        have = ", ".join(x["version"] for x in candidates)
        raise ValueError(
            f"requires {text!r}: no {tool} satisfies {spec!r} (published: {have})")
    return max(ok, key=lambda x: _vkey(x["version"]))


def _vkey(version):
    """Numeric sort key for a version string ("22.23.4", "21.0.12+101")."""
    main, _, build = version.partition("+")
    nums = [int(x) for x in __import__("re").findall(r"\d+", main)]
    bnum = [int(x) for x in __import__("re").findall(r"\d+", build)]
    return (nums, bnum)


def resolve(name, path=MATRIX):
    """Resolve a setup name to one entry.

    A VERSION is a dot-separated PREFIX, because people write `node-22`:

        node-22       -> node-22.23.4     (the newest 22.x we publish)
        node-22.23    -> node-22.23.4
        node-22.23.4  -> node-22.23.4     (exact always wins)

    Version matching is by whole segments, not characters: `node-2` does NOT
    match `node-22.23.4`, because "2" is not a segment of "22". A character
    prefix would silently install the wrong major version.

    Anything requiring another setup says so with `requires`; see resolve_chain.

    Returns None when nothing matches. Raises Ambiguous if two entries match equally.
    """
    entries = load(path)

    # 1) Exact directory match always wins (this is how `+component` names and
    #    fully spelled versions land).
    for e in entries:
        if e["dir"] == name:
            return e

    # A tool name may itself contain dashes (`rust-toolchain-x86_64-pc-windows-gnu`),
    # so the split is not "up to the first dash". Match every entry by asking
    # whether the name is `<its tool>-<a version prefix>`.
    matches = []
    for e in entries:
        prefix = e["tool"] + "-"
        if not name.startswith(prefix):
            continue
        want = name[len(prefix):]
        if not want:
            continue
        # The remainder must LOOK like a version. Without this, `swift-sdk-wasm`
        # matched the `swift` entry with want="sdk-wasm": a version key of ""
        # compares equal to everything, so asking for an SDK silently handed
        # back the compiler. A version always starts with a digit.
        if not want[0].isdigit():
            continue
        want_segments = want.split(".")
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


def resolve_chain(name, path=MATRIX, _seen=None):
    """Resolve a name AND everything it requires, dependencies first.

    `elixir-1` requires `erlang-28.0.0`, so installing elixir must install
    erlang first. The result is a list of entries in install order, each entry
    appearing once even if two setups share a dependency.

    Raises ValueError on an unknown name, a cycle, or a `requires` entry that
    does not resolve - all of which would otherwise produce a half-installed
    tree.
    """
    if _seen is None:
        done, active = set(), set()
    else:
        done, active = _seen.done, _seen.active

    # A `requires` entry is not just a name: it may carry a version constraint
    # (`erlang@>=29 <30`). resolve_requirement understands both, and raises a
    # message that names the published versions when a range matches nothing.
    e = resolve_requirement(name, path)
    if e["dir"] in done:
        return []                    # already scheduled by another branch
    if e["dir"] in active:
        # Marking nodes only AFTER recursion cannot detect a cycle: the second
        # visit happens before the first one finishes. Track the ACTIVE path.
        raise ValueError(f"requires cycle through {e['dir']!r}")

    active.add(e["dir"])
    out = []
    for req in e["requires"]:
        out.extend(resolve_chain(req, path, _Seen(done, active)))
    active.discard(e["dir"])

    done.add(e["dir"])
    out.append(e)
    return out


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
            try:
                chain = resolve_chain(argv[2])
            except ValueError as ex:
                avail = ", ".join(x["dir"] for x in load())
                sys.exit(f"matrixlib: {ex}\n  available: {avail}")
            print("\n".join(x["dir"] for x in chain))
            return 0

        if cmd == "plan":
            # The same thing, but annotated: which entries come from a
            # dependency rather than from the name given.
            try:
                chain = resolve_chain(argv[2])
            except ValueError as ex:
                sys.exit(f"matrixlib: {ex}")
            # The entry the user asked for is the LAST one in the chain (deps
            # come first); comparing against a fresh resolve() is wrong when the
            # name is itself a range or a bare tool.
            wanted = chain[-1]["dir"] if chain else None
            for x in chain:
                mark = "" if x["dir"] == wanted else "  (required)"
                print(f'{x["dir"]}{mark}')
            return 0
    except (ValueError, OSError) as e:
        sys.exit(f"matrixlib: {e}")

    sys.exit(f"matrixlib: unknown command '{cmd}'")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
