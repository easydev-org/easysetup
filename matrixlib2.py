"""Read matrix-nix.yml. Standard library only.

The old matrixlib resolved version ranges, followed `requires` chains and spelled
out artifact names, because every setup was a repacked upstream tarball whose
dependencies were ours to track. None of that survives the move to nix:

  * a setup IS one nixpkgs attribute, so there is nothing to resolve;
  * the dependency closure comes from `nix path-info -r`, not from `requires`;
  * the artifact name is `${tool}-${version}-debian-trixie-amd64.tar.zst`, derived.

So this parser does one thing: turn the manifest into a list of dicts with a
stable `dir` field, and answer `get <id> <field>`. Keeping it small is the point
- the previous file grew three separate resolvers and they drifted apart.

CLI:
    matrixlib2.py list                 one setup directory per line
    matrixlib2.py get <id> <field>     print a field (attr, version, tool, dir)
    matrixlib2.py json                 the whole manifest as JSON
    matrixlib2.py resolve <name>       resolve a user-typed name to a directory
"""

import json
import sys

MATRIX = "matrix-nix.yml"


def _scalar(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def _split_flow(inner):
    """Split a flow mapping on commas that are not inside quotes."""
    items, buf, quote = [], "", None
    for ch in inner:
        if quote:
            if ch == quote:
                quote = None
            else:
                buf += ch
        elif ch in "\"'":
            quote = ch
        elif ch == ",":
            items.append(buf)
            buf = ""
        else:
            buf += ch
    if buf.strip():
        items.append(buf)
    return [x.strip() for x in items if x.strip()]


def load(path=MATRIX):
    """Parse the manifest into entries. Each entry gets a derived `dir`."""
    entries = []
    cur = None
    in_setups = False
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped == "setups:":
            in_setups = True
            continue
        if not in_setups:
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 2 and stripped.startswith("- "):
            if cur is not None:
                entries.append(cur)
            rest = stripped[2:].strip()
            if rest.startswith("{"):
                # Flow mapping on one line: { tool: node, attr: "x", version: "1" }.
                # A 60-entry manifest is far easier to scan this way than with
                # five lines per setup.
                cur = {}
                inner = rest[1:]
                if inner.rstrip().endswith("}"):
                    inner = inner.rstrip()[:-1]
                for part in _split_flow(inner):
                    k, _, v = part.partition(":")
                    cur[k.strip()] = _scalar(v)
                continue
            cur = {}
            k, _, v = rest.partition(":")
            cur[k.strip()] = _scalar(v)
            continue
        if indent == 4 and cur is not None:
            k, _, v = stripped.partition(":")
            cur[k.strip()] = _scalar(v)
            continue
        raise ValueError("matrixlib2: unsupported line %r" % raw)
    if cur is not None:
        entries.append(cur)
    if not entries:
        raise ValueError("matrixlib2: no setups in %s" % path)

    for e in entries:
        for need in ("tool", "attr", "version"):
            if need not in e:
                raise ValueError("matrixlib2: entry missing %r: %r" % (need, e))
        # The directory name is how a setup is addressed everywhere else. It
        # carries the version so two versions of one tool can coexist.
        #
        # An optional `suffix` disambiguates two entries that would otherwise
        # collide. Python's tools are the case: python313Packages.mypy and
        # python314Packages.mypy are both 2.1.0, so both would be `mypy-2.1.0`
        # and the second would overwrite the first in the manifest's namespace.
        # With suffix "-py3.13" the entry is `mypy-2.1.0-py3.13`, which is what a
        # user types to get the 3.13 build.
        e["dir"] = "%s-%s%s" % (e["tool"], e["version"], e.get("suffix", ""))
        e.setdefault("bins", "bin")
        e["artifact"] = "%s-debian-trixie-amd64.tar.zst" % e["dir"]
    return entries


def by_dir(d, path=MATRIX):
    for e in load(path):
        if e["dir"] == d:
            return e
    return None


def resolve(name, path=MATRIX):
    """Resolve what a user typed to exactly one entry.

    Accepted, in priority order:
        swift-6.3.3   full directory
        mypy-py3.13   a tool plus a suffix, for entries that share a version
        swift-6       a version prefix, if unambiguous
        swift         the only entry with that tool name
    Anything ambiguous is an error rather than a silent pick: installing a
    different version than asked for is worse than failing.

    The order matters. `python-3.13` must hit the version-prefix rule before the
    bare-name rule, because there are two pythons and the bare name is ambiguous
    while the prefix is not. Checking them the other way round made
    `python-3.13` fail with "no setup matches", which is the wrong answer and a
    misleading message.
    """
    entries = load(path)
    for e in entries:
        if e["dir"] == name:
            return e

    # A full directory is the only exact form; everything below is a shorthand.
    #
    # Version prefix: `swift-6`, `python-3.13`, `node-24`. The separator after
    # the digits matters - a directory is `python-3.13.16`, so matching
    # `startswith("python-3.13-")` would never hit. Accepted boundaries are end
    # of string, `.` (a further version segment) and `-` (a suffix).
    #
    #
    # Two shapes reach here and they need different tests, so both are built and
    # the caller picks by precedence:
    #   name is a TOOL      python, node, go   -> match entries whose tool equals it
    #   name is TOOL-VER    python-3.13        -> match entries whose DIR starts with it
    # Testing only one shape is what made `go` pick up `go-tools` (a different
    # tool) while `python-3.13` matched nothing at all.
    as_tool = [e for e in entries if e["tool"] == name]
    as_dir = [e for e in entries
              if e["dir"] == name
              or e["dir"].startswith(name + ".")
              or e["dir"].startswith(name + "-")]
    # `<tool>-<suffix>`, for entries that share a version: `mypy-py3.13`.
    by_suffix = [e for e in entries
                 if e.get("suffix", "").lstrip("-") and
                 name == "%s-%s" % (e["tool"], e["suffix"].lstrip("-"))]
    # Prefer the interpretation that resolves to exactly one setup.
    for prefix in (as_dir, by_suffix, as_tool):
        if len(prefix) == 1:
            return prefix[0]

    # Nothing resolved to exactly one setup, so report the ambiguity that best
    # explains the input. Listing `go`'s candidates must not include `go-tools`:
    # that is a different tool, and naming it makes the error read as if `go` had
    # three versions.
    # `as_tool` is the one to report when the input is a bare tool name: it holds
    # only entries whose tool IS this name, so `go` lists its two versions rather
    # than also dragging in `go-tools`, which is a different tool.
    hits = as_tool if len(as_tool) > 1 else (as_dir if len(as_dir) > 1 else by_suffix)
    if len(hits) > 1:
        raise ValueError("matrixlib2: %r is ambiguous: %s"
                         % (name, ", ".join(e["dir"] for e in hits)))
    raise ValueError("matrixlib2: no setup matches %r" % name)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    path = MATRIX
    if cmd == "list":
        for e in load(path):
            print(e["dir"])
        return 0
    if cmd == "json":
        print(json.dumps(load(path), indent=2))
        return 0
    if cmd == "get":
        e = by_dir(argv[2], path) if len(argv) > 2 else None
        if e is None:
            sys.exit("matrixlib2: no setup %r" % (argv[2] if len(argv) > 2 else ""))
        field = argv[3] if len(argv) > 3 else "dir"
        if field not in e:
            sys.exit("matrixlib2: %r has no field %r" % (e["dir"], field))
        print(e[field])
        return 0
    if cmd == "resolve":
        e = resolve(argv[2], path)
        print(e["dir"])
        return 0
    sys.exit("matrixlib2: unknown command %r" % cmd)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
