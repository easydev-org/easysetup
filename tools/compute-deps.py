#!/usr/bin/env python3
"""Work out, from nix itself, which setups depend on which, and what to package.

WHY NOT HAND-WRITTEN DEPENDENCIES
---------------------------------
Writing `composer: deps: [php85]` in the manifest is a claim that has to be kept
true by hand. It goes stale the moment php moves a patch release, and a missing
entry only shows up as a broken binary on the consumer's machine.

Nix already knows: a package's closure is the exact transitive set of store paths
it needs, and that set is content-addressed. So the dependency graph is DERIVED
here, never asserted.

HOW, WITHOUT DOWNLOADING ANYTHING
---------------------------------
`nix eval .#<name>.outPath` resolves a store path from the derivation alone (it is
input-addressed, so no content is needed), and
`nix path-info --store https://cache.nixos.org -r <path>` walks the closure using
only the .narinfo metadata. Measured on this manifest: 40 setups in about 50
seconds, zero bytes of package content.

WHAT IT COMPUTES
----------------
base        the store paths present in EVERY setup's closure - glibc and its few
            companions. Published once, subtracted from everything else.
deps[setup] the other setups whose closure is a STRICT SUBSET of this one, so
            this setup can leave those paths out and let them provide them.
own[setup]  closure(setup) - union(closure(deps)) - base. The paths only this
            setup needs, which is all its tarball has to carry.

The result is written to closures.json, which install.sh reads at run time.
"""

import json
import os
import subprocess
import sys

NIX = (os.environ.get("NIX_BIN")
       or ("/nix/var/nix/profiles/default/bin/nix"
           if os.path.exists("/nix/var/nix/profiles/default/bin/nix") else "nix"))
CACHE = os.environ.get("EASYSETUP_CACHE", "https://cache.nixos.org")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402


def run(args, timeout=300):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def out_path(attr):
    """Resolve a flake attribute to its store path without building it."""
    r = run([NIX, "eval", "--raw", attr + ".outPath"])
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.strip()


def closure(path):
    """Every store path `path` needs, read from the binary cache's metadata."""
    r = run([NIX, "path-info", "--store", CACHE, "-r", path], timeout=600)
    if r.returncode != 0:
        return None
    return set(x for x in r.stdout.splitlines() if x.strip())


def main(argv):
    entries = matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))
    print("resolving %d setups" % len(entries))

    clos, outs = {}, {}
    for e in entries:
        p = out_path(e["attr"])
        if not p:
            print("  SKIP %-22s cannot resolve %s" % (e["dir"], e["attr"]))
            continue
        c = closure(p)
        if c is None:
            print("  SKIP %-22s cannot read closure" % e["dir"])
            continue
        outs[e["dir"]] = p
        clos[e["dir"]] = c
        print("  %-22s %4d paths" % (e["dir"], len(c)))

    if len(clos) < 2:
        sys.exit("need at least two resolvable setups")

    base = set.intersection(*clos.values())
    print()
    print("base: %d path(s) present in every closure" % len(base))
    for p in sorted(base):
        print("   ", p.split("-", 1)[-1])

    # deps[X] = setups whose closure is a STRICT subset of X's.
    deps = {}
    for name, c in clos.items():
        sub = [o for o, oc in clos.items() if o != name and oc < c]
        # Keep only maximal subsets: if A < B < C then C needs B only, and
        # listing both would install the same tree twice.
        maximal = [x for x in sub
                   if not any(x != y and clos[x] < clos[y] for y in sub)]
        deps[name] = sorted(maximal)

    own = {}
    for name, c in clos.items():
        cut = set(base)
        for d in deps[name]:
            cut |= clos[d]
        own[name] = sorted(c - cut)

    print()
    print("dependency edges (derived, not declared):")
    for name in sorted(deps):
        if deps[name]:
            print("  %-22s needs %s" % (name, ", ".join(deps[name])))

    print()
    print("packaging sizes (paths kept / total):")
    for name in sorted(own):
        print("  %-22s %4d / %4d" % (name, len(own[name]), len(clos[name])))

    # Sanity: base + deps + own must rebuild the original closure exactly.
    bad = 0
    for name, c in clos.items():
        rebuilt = set(base)
        for d in deps[name]:
            rebuilt |= clos[d]
        rebuilt |= set(own[name])
        if rebuilt != c:
            print("  BROKEN %s: differs by %d path(s)" % (name, len(c ^ rebuilt)))
            bad += 1
    if bad:
        sys.exit("%d setup(s) do not reconstruct - refusing to write" % bad)
    print()
    print("every setup reconstructs its full closure from base + deps + own")

    doc = {
        "generated_by": "tools/compute-deps.py",
        "note": "Derived from nix closures. Do not edit by hand.",
        "cache": CACHE,
        "base": sorted(base),
        "setups": {
            name: {
                "store": outs[name],
                "deps": deps[name],
                "own": own[name],
                "closure_size": len(clos[name]),
            }
            for name in sorted(clos)
        },
    }
    outfile = os.path.join(ROOT, "closures.json")
    with open(outfile, "w") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
    print()
    print("wrote %s (%d setups, %d base paths)"
          % (outfile, len(doc["setups"]), len(doc["base"])))


if __name__ == "__main__":
    main(sys.argv)
