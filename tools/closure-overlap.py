#!/usr/bin/env python3
"""How much do the closures of several setups share?

The question this answers: if every tarball ships a complete closure, how much of
that is downloaded more than once when a job asks for several tools?

nix makes the on-disk side free - two closures that need the same glibc refer to
the same content-hashed path, so the second unpack overwrites identical bytes.
The DOWNLOAD is not free: each tarball carries its own copy.

This measures the upper bound of what a shared-base scheme could save.

    tools/closure-overlap.py nixpkgs#nodejs nixpkgs#python3 ...
"""

import json
import subprocess
import sys

NIX = "/nix/var/nix/profiles/default/bin/nix"


def closure(attr):
    r = subprocess.run([NIX, "path-info", "-rS", "--json", attr],
                       capture_output=True, text=True, timeout=1800)
    out = r.stdout
    i = out.find("{")
    if i < 0:
        sys.exit("cannot read closure of %s:\n%s" % (attr, r.stderr[-400:]))
    return json.loads(out[i:])


def main(argv):
    attrs = argv[1:]
    if len(attrs) < 2:
        sys.exit(__doc__)

    sets, sizes = {}, {}
    for a in attrs:
        d = closure(a)
        sets[a] = set(d)
        sizes[a] = {p: v.get("narSize", 0) for p, v in d.items()}
        print("%-28s %3d paths  %7.1f MB" % (a, len(d), sum(sizes[a].values()) / 1048576))

    common = set.intersection(*sets.values())
    union = set.union(*sets.values())
    total_naive = sum(sum(sizes[a].values()) for a in attrs)
    # Size of the shared paths, counted once each.
    shared_bytes = 0
    for p in common:
        for a in attrs:
            if p in sizes[a]:
                shared_bytes += sizes[a][p]
                break

    print()
    print("per-setup sizes added together : %.1f MB" % (total_naive / 1048576))
    print("paths in the union             : %d" % len(union))
    print("paths common to ALL            : %d" % len(common))
    print("bytes those common paths hold  : %.1f MB (counted once each)"
          % (shared_bytes / 1048576))
    saved = shared_bytes * (len(attrs) - 1)
    print("a shared base would save       : %.1f MB of download (%.0f%%)"
          % (saved / 1048576, 100.0 * saved / total_naive))

    print()
    print("largest common paths:")
    common_sized = sorted((sizes[attrs[0]].get(p, 0), p) for p in common)[::-1][:12]
    for sz, p in common_sized:
        print("   %7.1f MB  %s" % (sz / 1048576, p.split("-", 1)[-1]))


if __name__ == "__main__":
    main(sys.argv)
