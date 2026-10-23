"""Read matrix-nix.yml. Standard library only.

The old matrixlib resolved version ranges, followed `requires` chains and spelled
out artifact names, because every setup was a repacked upstream tarball whose
dependencies were ours to track. None of that survives the move to nix:

  * a setup IS one nixpkgs attribute, so there is nothing to resolve;
  * the dependency closure comes from `nix path-info -r`, not from `requires`;
  * the artifact name is `${tool}-${version}-debian-trixie-amd64.tar.xz`, derived.

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
        e["dir"] = "%s-%s" % (e["tool"], e["version"])
        e.setdefault("bins", "bin")
        e["artifact"] = "%s-debian-trixie-amd64.tar.xz" % e["dir"]
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
        swift         the only entry with that tool name
        swift-6       a version prefix, if unambiguous
    Anything ambiguous is an error rather than a silent pick: installing a
    different version than asked for is worse than failing.
    """
    entries = load(path)
    for e in entries:
        if e["dir"] == name:
            return e
    same_tool = [e for e in entries if e["tool"] == name]
    if len(same_tool) == 1:
        return same_tool[0]
    if len(same_tool) > 1:
        raise ValueError("matrixlib2: %r is ambiguous: %s"
                         % (name, ", ".join(e["dir"] for e in same_tool)))
    prefix = [e for e in entries if e["dir"].startswith(name + "-")]
    if len(prefix) == 1:
        return prefix[0]
    if len(prefix) > 1:
        raise ValueError("matrixlib2: %r matches several: %s"
                         % (name, ", ".join(e["dir"] for e in prefix)))
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
