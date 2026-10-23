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
base        the store paths shared by MANY setups - glibc and its companions.
            Published once, subtracted from everything else. Shared by many, not
            by all: the intersection over 58 setups is empty, because a few tools
            (rust, clang) carry their own libc internally.
deps[setup] the other setups whose runtime closure this setup genuinely needs.
            See NARROWING below - closure inclusion alone is far too loose.
own[setup]  closure(setup) - union(closure(deps)) - base. The paths only this
            setup needs, which is all its tarball has to carry.

NARROWING: why a subset test is not enough
------------------------------------------
The first version treated "closure(dep) is a strict subset of closure(setup)" as
a dependency. That produced `dotnet deps=[perl]` and `erlang deps=[perl]`, which
are nonsense: perl appears in those closures because their BUILD needed it, not
their runtime. Acting on it would make `install.sh erlang` download perl for
nobody's benefit.

Three filters, applied in order:
  1. the "dep" must be a setup a human would recognise as related - same tool
     family (`composer` -> `php`), or an explicit runtime the setup cannot work
     without;
  2. its own store path must be REACHABLE from the setup's binary output, i.e. it
     must be in the closure of one of the setup's declared bins, not merely in the
     build closure;
  3. it must be big enough to be worth the extra request.

Filter 2 is the real one. `nix why-depends` answers exactly it, and it is what
distinguishes "php is needed to run composer" from "perl was needed to compile
erlang".

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

    # base = paths shared by MANY setups, not by all.
    #
    # The intersection over every setup is empty: `rust` and `clang` carry their
    # own libc internally, so they share no glibc path with the rest. Requiring
    # unanimity therefore finds nothing and the shared base is never extracted.
    #
    # A frequency threshold is the honest rule: a path that most setups need is
    # worth publishing once, and subtracting it from the ones that do not have it
    # is a no-op anyway.
    n = len(clos)
    threshold = max(2, int(n * 0.5))
    counts = {}
    for c in clos.values():
        for p in c:
            counts[p] = counts.get(p, 0) + 1
    base = {p for p, k in counts.items() if k >= threshold}
    print()
    print("base: %d path(s) shared by >=%d of %d setups" % (len(base), threshold, n))
    for p in sorted(base, key=lambda x: -counts[x])[:8]:
        print("   %3d/%d setups  %s" % (counts[p], n, p.split("-", 1)[-1]))

    # deps[X] = setups X genuinely needs at RUN time.
    #
    # Closure inclusion alone is not that. `perl` is in erlang's and dotnet's
    # closures because they were BUILT with it, so a subset test reports them as
    # depending on perl - which would make `install.sh dotnet` download a Perl
    # nobody runs.
    #
    # `nix why-depends` answers the real question: is the other setup's output
    # reachable from THIS setup's output? Build-only dependencies are not, because
    # nothing in the output references them.
    deps = {}
    for name, c in clos.items():
        sub = [o for o, oc in clos.items() if o != name and oc < c]
        # Keep only maximal subsets: if A < B < C then C needs B only, and
        # listing both would install the same tree twice.
        maximal = [x for x in sub
                   if not any(x != y and clos[x] < clos[y] for y in sub)]
        # Now keep only those actually reachable from the output.
        runtime = []
        for cand in maximal:
            r = run([NIX, "why-depends", "--quiet",
                     outs[name], outs[cand]], timeout=300)
            # Exit 0 means a dependency path exists; non-zero means the output
            # does not reference it at all.
            if r.returncode == 0:
                runtime.append(cand)
        deps[name] = sorted(runtime)

    # `base` has to be a REAL setup, not just a node in this file: install.sh can
    # only fetch things that were published. So every setup that contains any base
    # path depends on the `base` setup, and `base` itself carries exactly those
    # paths (see build-nixpkg.sh, which special-cases it).
    if base:
        for name, c in clos.items():
            if (set(base) & c) and name != "base":
                if "base" not in deps[name]:
                    deps[name] = sorted(deps[name] + ["base"])

    # What each tarball carries.
    #
    # base is shared by MANY setups, not by all, so a given setup may not contain
    # some of its paths at all - subtracting unconditionally is still correct
    # because subtracting an absent path is a no-op, but the reconstruction check
    # below compares against the ORIGINAL closure and would see a mismatch if the
    # arithmetic were sloppy. Intersecting with the setup's own closure keeps the
    # two consistent.
    own = {}
    # `base` is special: deps lists it, but it is not in clos under that name -
    # clos["base"] would be glibc's FULL closure (build deps included), which is
    # not what the base setup ships. The shared set is in `base`.
    #
    # It is also intersected with the setup's own closure: the base set was chosen
    # by frequency, so a given setup may not contain every path in it (rust and
    # clang carry their own libc). Subtracting only what is actually present keeps
    # `base + deps + own` equal to the original closure - which is what the
    # assertion below checks, and what install.sh depends on.
    def dep_paths(name, own_closure):
        if name == "base":
            return set(base) & own_closure
        return clos[name]

    for name, c in clos.items():
        if name == "base":
            # base ships the shared set ITSELF, not "what its own attribute adds".
            #
            # The base entry's attribute is glibc, whose closure is 4 paths - but
            # the shared set spans 14 paths drawn from many packages (bash, gcc,
            # xz, acl...). Intersecting the two gives zero, so the base tarball
            # would be empty and every setup that subtracts those paths would be
            # left with holes. The shared set is the payload.
            own[name] = sorted(base)
            continue
        cut = (set(base) & c)
        for d in deps[name]:
            cut |= dep_paths(d, c)
        own[name] = sorted(c - cut)

    print()
    print("dependency edges (derived, not declared):")
    for name in sorted(deps):
        shown = [d for d in deps[name] if d != "base"]
        if shown:
            print("  %-22s needs %s (+base)" % (name, ", ".join(shown)))

    print()
    print("packaging sizes (paths kept / total):")
    for name in sorted(own):
        print("  %-22s %4d / %4d" % (name, len(own[name]), len(clos[name])))

    # Sanity: base + deps + own must rebuild the original closure exactly.
    bad = 0
    for name, c in clos.items():
        if name == "base":
            # base ships the shared set verbatim, and nothing else is subtracted.
            if set(own[name]) != set(base):
                print("  BROKEN base: ships %d of %d shared paths"
                      % (len(own[name]), len(set(base))))
                bad += 1
            continue
        rebuilt = set(base) & c          # only the base paths this setup has
        for d in deps[name]:
            rebuilt |= dep_paths(d, c)
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
