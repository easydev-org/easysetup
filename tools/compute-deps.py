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

# Which architecture this run computes for. The graph is not the same for both:
# a package can depend on different things once the platform changes, and the
# store paths themselves differ. Setting ARCH turns every nix invocation below
# into an evaluation for that system.
#
# An arm64 graph is computed on an amd64 runner by evaluating, never building -
# every path in it is in cache.nixos.org, which the earlier probe established.
ARCH = os.environ.get("ARCH", "amd64")
NIX_SYSTEM = {"amd64": "x86_64-linux", "arm64": "aarch64-linux"}.get(ARCH)
if NIX_SYSTEM is None:
    raise SystemExit("compute-deps: ARCH must be amd64 or arm64, got %r" % ARCH)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402


def run(args, timeout=300):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def out_path(dir_name):
    """Resolve a setup's REAL store path.

    Takes the DIRECTORY name (`base-2.44`, `jq-1.8.2`), not the manifest's
    attribute (`nixpkgs#glibc`). The flake exposes `packages.<system>.<dir>`, so
    asking for `.#"glibc"` fails - there is no such attribute - even though
    `nixpkgs#glibc` resolves fine through the channel.

    That distinction is why the old code had a channel fallback and appeared to
    work: every flake lookup failed, the fallback answered, and the recorded paths
    came from the channel rather than the lock.

    Two decisions here, both from observed failures:

    Resolved through OUR flake, not `nixpkgs#...`: the registry's nixpkgs has
    allowUnfree false, so anything unfree resolved to nothing and vanished from
    the graph. flake.nix sets allowUnfree.

    Read with `nix build --print-out-paths`, not `.outPath`: for a few packages
    the two disagree, and `.outPath` gives a path that is not valid. crystal is
    the case in point - `.outPath` yields `.../crystal-1.21.1` which does not
    exist, while the build produces `.../crystal-1.21.1-bin`. Asking the build
    what it makes is the only form that is true for every setup.

    The setup name contains dots (jq-1.8.2), so it is quoted inside the attribute
    path or nix reads the dots as separators.
    """
    name = dir_name
    # ONLY our flake, never the bare `nixpkgs#<attr>` that the manifest carries.
    #
    # There used to be a fallback to that second form, and it quietly broke the
    # one guarantee this file exists to provide: `nixpkgs#ameba` resolves through
    # NIX_PATH's channel, not through flake.lock. The graph would then record the
    # channel's store path while build-nixpkg.sh built the locked one - the two
    # differ as soon as the channel moves - and the subtraction would remove paths
    # the tarball did not contain. The symptom was "bin/ is empty in the staged
    # copy" on a completely correct build.
    #
    # If the flake cannot resolve an attribute, that is a real answer: this setup
    # is not available here.
    for ref in ('.#%s' % _quoted(name),):
        # max-jobs 0: this must never compile. Resolving a setup's output path is
        # a lookup, and a lookup that has to build its answer means the setup is
        # not publishable - which the cache check in closure() then confirms. Any
        # compile here would also be invisible: it would just make the graph step
        # take an hour instead of a minute.
        r = run([NIX, "build", "--no-link", "--print-out-paths",
                 "--system", NIX_SYSTEM, "--option", "max-jobs", "0", ref],
                timeout=1800)
        if r.returncode != 0:
            # Print nix's own message. Without it "cannot resolve" tells you
            # nothing about whether the attribute is missing, the flake is
            # broken, or the system is not in `systems`.
            err = (r.stderr or "").strip().splitlines()
            if err:
                print("      nix said: %s" % err[-1][:160])
            continue
        lines = [x for x in r.stdout.splitlines() if x.strip()]
        if not lines:
            continue
        # A multi-output package lists one line per output and the order is not
        # meaningful - both head and tail landed on `-man` for different setups,
        # recording a documentation output as if it were the program. Prefer the
        # output that actually holds executables.
        for p in lines:
            if os.path.isdir(os.path.join(p, "bin")) or \
               os.path.isdir(os.path.join(p, "sbin")):
                return p
        return lines[0]
    return None


def _quoted(name):
    """Quote an attribute name for a nix attribute path."""
    return '"%s"' % name


def closure(path, name=None):
    """Every store path `path` needs, read from the binary cache's metadata."""
    r = run([NIX, "path-info", "--store", CACHE, "-r", path], timeout=600)
    if r.returncode == 0 and r.stdout.strip():
        return set(x for x in r.stdout.splitlines() if x.strip())

    # Not in the cache, so this setup cannot be published. That is the answer -
    # there is deliberately no "build it locally" fallback any more.
    #
    # There used to be one, and it was the wrong shape of fix: it made the graph
    # complete by compiling the missing piece on the CI machine, which meant a
    # published tarball could contain something nothing else had ever built and no
    # cache could ever re-produce. The project only ships what cache.nixos.org
    # already has, so a cache miss here is a reason to leave the setup out, not to
    # work around it.
    #
    # The caller prints the name and skips it; `probe-closure-fails.py` reports the
    # same set so the omission is visible in the run rather than silent.
    print("      (not in cache: %s)" % path.split("-", 1)[-1])
    return None


def main(argv):
    entries = matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))
    # Drop what this architecture cannot have before anything else. swift and
    # friends have no aarch64 derivation, so including them would make the arm64
    # graph depend on setups that do not exist and fail at every reference.
    skipped = [e for e in entries if not matrixlib2.available_on(e, ARCH)]
    if skipped:
        print("not available on %s: %s"
              % (ARCH, ", ".join(e["dir"] for e in skipped)))
    entries = [e for e in entries if matrixlib2.available_on(e, ARCH)]
    print("resolving %d setups" % len(entries))

    clos, outs = {}, {}
    for e in entries:
        p = out_path(e["dir"])
        if not p:
            print("  SKIP %-22s cannot resolve .#\"%s\" (attr %s)"
                  % (e["dir"], e["dir"], e["attr"]))
            continue
        c = closure(p, name=e["dir"])
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
    # only fetch things that were published.
    #
    # Its directory is `<tool>-<version>` like every other entry, so the name is
    # not the literal "base" - deriving it from the manifest avoids the bug where
    # both "base" and "base-2.44" ended up in deps, one of which is not a
    # directory that exists.
    base_name = None
    for e in entries:
        if e["tool"] == "base":
            base_name = e["dir"]
            break
    if base and base_name:
        for name, c in clos.items():
            if (set(base) & c) and name != base_name:
                if base_name not in deps[name]:
                    deps[name] = sorted(deps[name] + [base_name])

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
        if name == base_name:
            return set(base) & own_closure
        return clos[name]

    for name, c in clos.items():
        if name == base_name:
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

    # Overlapping `own` lists are recorded rather than rearranged.
    #
    # Two setups can legitimately share a store path: java and maven both contain
    # set-java-classpath-hook, but neither depends on the other, so it stays in both
    # own lists. 3050 pairs overlapped this way, over 392 distinct paths - 57% of
    # the payload duplicated.
    #
    # Moving each shared path to a single owner was tried and reverted: any
    # assignment creates cycles (bazel -> diffutils -> coreutils -> box -> bazel),
    # because sharing is not directional. Pushing all 392 into base was also tried:
    # it makes `install jq` download 400 paths to get 3.
    #
    # So the duplication stays, and the INSTALLER is what has to cope with writing a
    # path that already exists - which is the honest place for it, since that is
    # what "two tarballs contain the same file" means. The count is printed so the
    # cost is visible rather than discovered.
    holders = {}
    for name, paths in own.items():
        if name == base_name:
            continue
        for p in paths:
            holders.setdefault(p, []).append(name)
    shared = {p: ns for p, ns in holders.items() if len(ns) > 1}
    if shared:
        dup = sum(len(ns) - 1 for ns in shared.values())
        print()
        print("%d path(s) are shared by two or more setups (%d duplicate copies);"
              % (len(shared), dup))
        print("the installer overwrites them rather than failing")
        for p, ns in sorted(shared.items(), key=lambda kv: -len(kv[1]))[:5]:
            print("   %3d setups  %s" % (len(ns), p.split("-", 1)[-1]))

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
        if name == base_name:
            # base ships the shared set verbatim, so its payload is exactly that
            # set - not "what its glibc closure adds". Checking it against the
            # closure would be checking the wrong thing.
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
        "arch": ARCH,
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
    # One file per architecture: the store paths are different, so one graph
    # cannot describe both. The installer picks the file matching its own GOARCH.
    outfile = os.path.join(ROOT, "closures-%s.json" % ARCH)
    with open(outfile, "w") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
    print()
    print("wrote %s (%d setups, %d base paths)"
          % (outfile, len(doc["setups"]), len(doc["base"])))


if __name__ == "__main__":
    main(sys.argv)
